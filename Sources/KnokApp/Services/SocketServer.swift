// PLACEHOLDER — to be implemented by agent
import Foundation
import KnokCore

final class SocketServer: @unchecked Sendable {
    private let alertEngine: AlertEngine
    private var listenFD: Int32 = -1
    private var isRunning = false
    private var acceptThread: Thread?

    init(alertEngine: AlertEngine) {
        self.alertEngine = alertEngine
    }

    func start() {
        // Remove stale socket
        unlink(KnokConstants.socketPath)

        // Create socket
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let pathBytes = KnokConstants.socketPath.utf8CString
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(listenFD)
            return
        }

        // Listen
        guard listen(listenFD, 5) == 0 else {
            close(listenFD)
            return
        }

        isRunning = true

        // Accept connections on background thread
        acceptThread = Thread {
            self.acceptLoop()
        }
        acceptThread?.start()
    }

    func stop() {
        isRunning = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
    }

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(listenFD, sockPtr, &addrLen)
                }
            }

            if clientFD < 0 {
                if !isRunning { break }
                continue
            }

            // Handle client on a new thread
            Thread.detachNewThread {
                self.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        // Read payload
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = recv(fd, &buffer, buffer.count, 0)
            if bytesRead <= 0 { return }
            data.append(contentsOf: buffer[..<bytesRead])
            if buffer[..<bytesRead].contains(0x0A) { break }
        }

        // Trim newline
        if data.last == 0x0A { data.removeLast() }

        // Decode payload
        guard let payload = try? JSONDecoder().decode(AlertPayload.self, from: data) else {
            let error = AlertResponse(action: "error")
            if let errorData = try? JSONEncoder().encode(error) {
                var msg = errorData
                msg.append(0x0A)
                _ = msg.withUnsafeBytes { buf in
                    Darwin.send(fd, buf.baseAddress!, buf.count, 0)
                }
            }
            return
        }

        // Show alert and get response (synchronous bridge to main thread)
        let semaphore = DispatchSemaphore(value: 0)
        var response = AlertResponse.dismissed

        DispatchQueue.main.async {
            self.alertEngine.showAlert(payload: payload) { result in
                response = result
                semaphore.signal()
            }
        }

        // Wait for user response (with timeout if TTL > 0)
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
            var msg = responseData
            msg.append(0x0A)
            _ = msg.withUnsafeBytes { buf in
                Darwin.send(fd, buf.baseAddress!, buf.count, 0)
            }
        }
    }
}
