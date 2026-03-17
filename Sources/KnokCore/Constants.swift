import Foundation

public enum KnokConstants {
    public static let socketDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".knok")
    public static let socketPath = socketDir.appendingPathComponent("knok.sock").path
    public static let version = "0.1.0"
    public static let appName = "Knok"

    /// Max payload size (1MB)
    public static let maxPayloadSize = 1_048_576

    /// Default response timeout in seconds
    public static let defaultTimeout: TimeInterval = 300
}
