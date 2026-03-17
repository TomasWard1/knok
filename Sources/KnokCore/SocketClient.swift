import Foundation

/// Client that connects to the Knok app via Unix Domain Socket
public final class SocketClient: Sendable {
    private let socketPath: String

    public init(socketPath: String = KnokConstants.socketPath) {
        self.socketPath = socketPath
    }

    /// Send an alert payload and wait for the response
    public func send(_ payload: AlertPayload, timeout: TimeInterval = KnokConstants.defaultTimeout) throws -> AlertResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw KnokError.socketCreationFailed(errno: errno)
        }
        defer { close(fd) }

        // Connect to Unix socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw KnokError.socketPathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw KnokError.connectionFailed(errno: errno)
        }

        // Set socket timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Encode and send payload
        let encoder = JSONEncoder()
        var data = try encoder.encode(payload)
        data.append(contentsOf: [0x0A]) // newline delimiter

        let sent = data.withUnsafeBytes { buf in
            Darwin.send(fd, buf.baseAddress!, buf.count, 0)
        }
        guard sent == data.count else {
            throw KnokError.sendFailed(errno: errno)
        }

        // Read response
        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = recv(fd, &buffer, buffer.count, 0)
            if bytesRead <= 0 {
                if bytesRead == 0 { break }
                throw KnokError.receiveFailed(errno: errno)
            }
            responseData.append(contentsOf: buffer[..<bytesRead])
            if buffer[..<bytesRead].contains(0x0A) { break }
        }

        // Trim newline
        if responseData.last == 0x0A {
            responseData.removeLast()
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AlertResponse.self, from: responseData)
    }
}
