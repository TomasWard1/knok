import Foundation
import KnokCore

final class HTTPServer: @unchecked Sendable {
    private let alertEngine: AlertEngine
    private let configManager: ConfigManager
    private let webhookHandler: GitHubWebhookHandler?
    private var listenFDs: [Int32] = []
    private var isRunning = false
    private var acceptThreads: [Thread] = []

    init(alertEngine: AlertEngine, configManager: ConfigManager, webhookHandler: GitHubWebhookHandler? = nil) {
        self.alertEngine = alertEngine
        self.configManager = configManager
        self.webhookHandler = webhookHandler
    }

    func start() {
        let config = configManager.config
        guard config.httpServer.enabled else { return }

        let port = config.httpServer.port

        // Always listen on localhost (for Tailscale Funnel)
        var addresses = ["127.0.0.1"]

        // Also listen on Tailscale IP if available (for AI agents on the tailnet)
        if let tailscaleIP = Self.tailscaleIPv4(), tailscaleIP != "127.0.0.1" {
            addresses.append(tailscaleIP)
        }

        for address in addresses {
            if let fd = createListener(address: address, port: port) {
                listenFDs.append(fd)
                let thread = Thread { self.acceptLoop(fd: fd) }
                acceptThreads.append(thread)
            }
        }

        guard !listenFDs.isEmpty else { return }
        isRunning = true
        acceptThreads.forEach { $0.start() }
    }

    private func createListener(address: String, port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(address)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return nil
        }

        guard listen(fd, 5) == 0 else {
            close(fd)
            return nil
        }

        return fd
    }

    /// Finds the Tailscale utun interface IPv4 address (100.x.x.x)
    private static func tailscaleIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("utun"),
                  ptr.pointee.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                                     &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            if result == 0 {
                let ip = String(cString: hostname)
                if ip.hasPrefix("100.") { return ip }
            }
        }
        return nil
    }

    func stop() {
        isRunning = false
        for fd in listenFDs {
            close(fd)
        }
        listenFDs = []
        acceptThreads = []
    }

    func restart() {
        stop()
        // Small delay to allow socket release
        Thread.sleep(forTimeInterval: 0.1)
        start()
    }

    // MARK: - Accept Loop

    private func acceptLoop(fd listenFD: Int32) {
        while isRunning {
            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(listenFD, sockPtr, &addrLen)
                }
            }

            if clientFD < 0 {
                if !isRunning { break }
                continue
            }

            Thread.detachNewThread {
                self.handleClient(fd: clientFD)
            }
        }
    }

    // MARK: - Client Handler

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        // Set read timeout (30s)
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Read HTTP request (headers + body)
        guard let request = readHTTPRequest(fd: fd) else {
            sendResponse(fd: fd, status: 400, statusText: "Bad Request", body: errorJSON("Failed to read request"))
            return
        }

        // Only POST allowed
        guard request.method == "POST" else {
            sendResponse(fd: fd, status: 405, statusText: "Method Not Allowed", body: errorJSON("Only POST is allowed"))
            return
        }

        switch request.path {
        case "/alert":
            handleAlertRequest(fd: fd, request: request)
        case "/github/webhook":
            handleWebhookRequest(fd: fd, request: request)
        default:
            sendResponse(fd: fd, status: 404, statusText: "Not Found", body: errorJSON("Unknown endpoint"))
        }
    }

    // MARK: - Alert Handler

    private func handleAlertRequest(fd: Int32, request: HTTPRequest) {
        // Auth check
        let config = configManager.config
        if config.httpServer.authRequired {
            guard let authHeader = request.headers["authorization"],
                  authHeader.hasPrefix("Bearer "),
                  String(authHeader.dropFirst(7)) == config.httpServer.token else {
                sendResponse(fd: fd, status: 401, statusText: "Unauthorized", body: errorJSON("Invalid or missing token"))
                return
            }
        }

        // Parse body
        guard let bodyData = request.body,
              let payload = try? JSONDecoder().decode(AlertPayload.self, from: bodyData).sanitized() else {
            sendResponse(fd: fd, status: 400, statusText: "Bad Request", body: errorJSON("Invalid JSON or missing required fields (level, title)"))
            return
        }

        // Dispatch alert (same pattern as SocketServer)
        let semaphore = DispatchSemaphore(value: 0)
        var response = AlertResponse.dismissed

        DispatchQueue.main.async {
            self.alertEngine.showAlert(payload: payload) { result in
                response = result
                semaphore.signal()
            }
        }

        // Wait for response — TTL auto-dismiss is handled by WindowManager
        // when the alert is actually displayed, not when it's enqueued
        semaphore.wait()

        // Send response
        if let responseData = try? JSONEncoder().encode(response) {
            sendResponse(fd: fd, status: 200, statusText: "OK", body: responseData)
        }
    }

    // MARK: - Webhook Handler

    private func handleWebhookRequest(fd: Int32, request: HTTPRequest) {
        guard let handler = webhookHandler else {
            sendResponse(fd: fd, status: 503, statusText: "Service Unavailable", body: errorJSON("Webhook handler not configured"))
            return
        }

        guard let bodyData = request.body else {
            sendResponse(fd: fd, status: 400, statusText: "Bad Request", body: errorJSON("Missing body"))
            return
        }

        let headers = request.headers

        // Return 200 immediately — GitHub has a 10s timeout
        sendResponse(fd: fd, status: 200, statusText: "OK", body: Data("{\"ok\":true}".utf8))

        // Process async on main actor
        DispatchQueue.main.async {
            let _ = handler.handleRequest(headers: headers, body: bodyData)
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?
    }

    private func readHTTPRequest(fd: Int32) -> HTTPRequest? {
        var headerData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let headerEnd = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

        // Read until we find end of headers
        while true {
            let bytesRead = recv(fd, &buffer, buffer.count, 0)
            if bytesRead <= 0 { return nil }
            headerData.append(contentsOf: buffer[..<bytesRead])

            if headerData.range(of: headerEnd) != nil { break }
            if headerData.count > KnokConstants.maxPayloadSize { return nil }
        }

        // Split headers and any body data already read
        guard let separatorRange = headerData.range(of: headerEnd) else { return nil }
        let headersRaw = headerData[..<separatorRange.lowerBound]
        var bodyData = Data(headerData[separatorRange.upperBound...])

        guard let headersString = String(data: Data(headersRaw), encoding: .utf8) else { return nil }

        // Parse request line
        let lines = headersString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // Read remaining body if needed
        if let contentLengthStr = headers["content-length"],
           let contentLength = Int(contentLengthStr),
           contentLength > 0 {
            while bodyData.count < contentLength {
                let remaining = contentLength - bodyData.count
                let readSize = min(remaining, 4096)
                var readBuffer = [UInt8](repeating: 0, count: readSize)
                let bytesRead = recv(fd, &readBuffer, readSize, 0)
                if bytesRead <= 0 { break }
                bodyData.append(contentsOf: readBuffer[..<bytesRead])
            }
        }

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: bodyData.isEmpty ? nil : bodyData
        )
    }

    // MARK: - HTTP Response

    private func sendResponse(fd: Int32, status: Int, statusText: String, body: Data?) {
        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Connection: close\r\n"
        let bodyLen = body?.count ?? 0
        response += "Content-Length: \(bodyLen)\r\n"
        response += "\r\n"

        var data = Data(response.utf8)
        if let body = body {
            data.append(body)
        }

        _ = data.withUnsafeBytes { buf in
            Darwin.send(fd, buf.baseAddress!, buf.count, 0)
        }
    }

    private func errorJSON(_ message: String) -> Data {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        return Data("{\"error\":\"\(escaped)\"}".utf8)
    }
}
