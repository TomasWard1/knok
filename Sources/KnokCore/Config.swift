import Foundation

// MARK: - Models

public struct KnokConfig: Codable, Sendable {
    public var httpServer: HTTPServerConfig

    public init(httpServer: HTTPServerConfig = .default) {
        self.httpServer = httpServer
    }
}

public struct HTTPServerConfig: Codable, Sendable {
    public var enabled: Bool
    public var port: UInt16
    public var authRequired: Bool
    public var token: String

    public init(enabled: Bool = true, port: UInt16 = KnokConstants.defaultHTTPPort, authRequired: Bool = true, token: String? = nil) {
        self.enabled = enabled
        self.port = port
        self.authRequired = authRequired
        self.token = token ?? Self.generateToken()
    }

    public static let `default` = HTTPServerConfig()

    public static func generateToken() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var result = "knk_"
        for _ in 0..<32 {
            result.append(chars[Int.random(in: 0..<chars.count)])
        }
        return result
    }
}

// MARK: - ConfigManager

public final class ConfigManager: @unchecked Sendable {
    private var _config: KnokConfig
    private let lock = NSLock()

    public var config: KnokConfig {
        lock.lock()
        defer { lock.unlock() }
        return _config
    }

    public init() {
        _config = Self.load()
    }

    public func update(_ transform: (inout KnokConfig) -> Void) {
        lock.lock()
        transform(&_config)
        let snapshot = _config
        lock.unlock()
        Self.save(snapshot)
    }

    // MARK: - File I/O

    private static func load() -> KnokConfig {
        let path = KnokConstants.configPath
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(KnokConfig.self, from: data) else {
            let config = KnokConfig()
            save(config)
            return config
        }
        return config
    }

    private static func save(_ config: KnokConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(at: KnokConstants.socketDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: KnokConstants.configPath, contents: data)
    }
}
