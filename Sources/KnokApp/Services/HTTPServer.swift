import Foundation
import KnokCore

final class HTTPServer: @unchecked Sendable {
    private let alertEngine: AlertEngine
    private let configManager: ConfigManager
    private var listenFD: Int32 = -1
    private var isRunning = false
    private var acceptThread: Thread?

    init(alertEngine: AlertEngine, configManager: ConfigManager) {
        self.alertEngine = alertEngine
        self.configManager = configManager
    }

    func start() {
        let config = configManager.config
        guard config.httpServer.enabled else { return }

        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }

        // Allow address reuse
        var reuse: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to 0.0.0.0:port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = config.httpServer.port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(listenFD)
            listenFD = -1
            return
        }

        guard listen(listenFD, 5) == 0 else {
            close(listenFD)
            listenFD = -1
            return
        }

        isRunning = true
        acceptThread = Thread { self.acceptLoop() }
        acceptThread?.start()
    }

    func stop() {
        isRunning = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
    }

    func restart() {
        stop()
        // Small delay to allow socket release
        Thread.sleep(forTimeInterval: 0.1)
        start()
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
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

        // Only /alert endpoint
        guard request.path == "/alert" else {
            sendResponse(fd: fd, status: 404, statusText: "Not Found", body: errorJSON("Unknown endpoint"))
            return
        }

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
              let payload = try? JSONDecoder().decode(AlertPayload.self, from: bodyData) else {
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

        if payload.ttl > 0 {
            let result = semaphore.wait(timeout: .now() + .seconds(payload.ttl))
            if result == .timedOut {
                response = .timeout
                DispatchQueue.main.async {
                    self.alertEngine.dismissCurrent()
                }
            }
        } else {
            semaphore.wait()
        }

        // Send response
        if let responseData = try? JSONEncoder().encode(response) {
            sendResponse(fd: fd, status: 200, statusText: "OK", body: responseData)
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
