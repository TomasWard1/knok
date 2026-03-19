import Testing
import Foundation
@testable import KnokCore

@Suite("HTTPServerConfig Tests")
struct HTTPServerConfigTests {

    @Test("Default config has expected values")
    func defaultConfig() {
        let config = HTTPServerConfig.default
        #expect(config.enabled == true)
        #expect(config.port == 9999)
        #expect(config.authRequired == true)
        #expect(config.token.hasPrefix("knk_"))
    }

    @Test("Token has knk_ prefix")
    func tokenPrefix() {
        let token = HTTPServerConfig.generateToken()
        #expect(token.hasPrefix("knk_"))
    }

    @Test("Token is 36 characters (4 prefix + 32 random)")
    func tokenLength() {
        let token = HTTPServerConfig.generateToken()
        #expect(token.count == 36)
    }

    @Test("Token contains only lowercase alphanumeric after prefix")
    func tokenCharset() {
        let token = HTTPServerConfig.generateToken()
        let suffix = String(token.dropFirst(4))
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        for scalar in suffix.unicodeScalars {
            #expect(allowed.contains(scalar), "Unexpected character: \(scalar)")
        }
    }

    @Test("Generated tokens are unique")
    func tokenUniqueness() {
        let tokens = (0..<100).map { _ in HTTPServerConfig.generateToken() }
        let unique = Set(tokens)
        #expect(unique.count == tokens.count)
    }

    @Test("Custom init overrides defaults")
    func customInit() {
        let config = HTTPServerConfig(enabled: false, port: 8080, authRequired: false, token: "knk_custom")
        #expect(config.enabled == false)
        #expect(config.port == 8080)
        #expect(config.authRequired == false)
        #expect(config.token == "knk_custom")
    }

    @Test("Nil token generates one automatically")
    func nilTokenAutoGenerates() {
        let config = HTTPServerConfig(enabled: true, port: 9999, authRequired: true, token: nil)
        #expect(config.token.hasPrefix("knk_"))
        #expect(config.token.count == 36)
    }
}

@Suite("KnokConfig Tests")
struct KnokConfigTests {

    @Test("Default KnokConfig wraps default HTTPServerConfig")
    func defaultWrapping() {
        let config = KnokConfig()
        #expect(config.httpServer.enabled == true)
        #expect(config.httpServer.port == 9999)
    }

    @Test("Encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = KnokConfig(httpServer: HTTPServerConfig(
            enabled: false, port: 8080, authRequired: false, token: "knk_testtoken123456789012345678"
        ))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KnokConfig.self, from: data)
        #expect(decoded.httpServer.enabled == original.httpServer.enabled)
        #expect(decoded.httpServer.port == original.httpServer.port)
        #expect(decoded.httpServer.authRequired == original.httpServer.authRequired)
        #expect(decoded.httpServer.token == original.httpServer.token)
    }

    @Test("JSON structure matches expected schema")
    func jsonStructure() throws {
        let config = KnokConfig(httpServer: HTTPServerConfig(
            enabled: true, port: 9999, authRequired: true, token: "knk_abc123"
        ))
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let httpServer = json["httpServer"] as! [String: Any]
        #expect(httpServer["enabled"] as? Bool == true)
        #expect(httpServer["port"] as? Int == 9999)
        #expect(httpServer["authRequired"] as? Bool == true)
        #expect(httpServer["token"] as? String == "knk_abc123")
    }
}

@Suite("ConfigManager Tests")
struct ConfigManagerTests {

    private func makeTempConfig() -> (path: String, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("config.json").path
        return (path, dir)
    }

    @Test("ConfigManager loads or creates config")
    func loadsConfig() {
        let tmp = makeTempConfig()
        let manager = ConfigManager(configPath: tmp.path, configDir: tmp.dir)
        let config = manager.config
        #expect(config.httpServer.token.hasPrefix("knk_"))
        #expect(config.httpServer.port == 9999 || config.httpServer.port > 0)
        try? FileManager.default.removeItem(at: tmp.dir)
    }

    @Test("ConfigManager update mutates config")
    func updateMutates() {
        let tmp = makeTempConfig()
        let manager = ConfigManager(configPath: tmp.path, configDir: tmp.dir)
        let originalToken = manager.config.httpServer.token

        manager.update { config in
            config.httpServer.port = 7777
        }

        #expect(manager.config.httpServer.port == 7777)
        #expect(manager.config.httpServer.token == originalToken)
        try? FileManager.default.removeItem(at: tmp.dir)
    }

    @Test("ConfigManager persists to disk")
    func persistsToDisk() throws {
        let tmp = makeTempConfig()
        let manager = ConfigManager(configPath: tmp.path, configDir: tmp.dir)
        let testToken = "knk_testpersist000000000000000000"

        manager.update { config in
            config.httpServer.token = testToken
        }

        // Read file directly
        let data = try #require(FileManager.default.contents(atPath: tmp.path))
        let diskConfig = try JSONDecoder().decode(KnokConfig.self, from: data)
        #expect(diskConfig.httpServer.token == testToken)
        try? FileManager.default.removeItem(at: tmp.dir)
    }
}
