import Foundation

/// Errors that can occur in Knok operations
public enum KnokError: Error, LocalizedError {
    case socketCreationFailed(errno: Int32)
    case socketPathTooLong
    case connectionFailed(errno: Int32)
    case sendFailed(errno: Int32)
    case receiveFailed(errno: Int32)
    case appNotRunning
    case invalidResponse
    case timeout

    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let errno):
            return "Failed to create socket: \(String(cString: strerror(errno)))"
        case .socketPathTooLong:
            return "Socket path exceeds maximum length"
        case .connectionFailed(let errno):
            if errno == ECONNREFUSED || errno == ENOENT {
                return "Knok app is not running. Launch Knok.app first."
            }
            return "Failed to connect: \(String(cString: strerror(errno)))"
        case .sendFailed(let errno):
            return "Failed to send data: \(String(cString: strerror(errno)))"
        case .receiveFailed(let errno):
            return "Failed to receive response: \(String(cString: strerror(errno)))"
        case .appNotRunning:
            return "Knok app is not running. Launch Knok.app first."
        case .invalidResponse:
            return "Invalid response from Knok app"
        case .timeout:
            return "Timed out waiting for response"
        }
    }
}
