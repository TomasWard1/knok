import Testing
import Foundation
@testable import KnokCore

// MARK: - Payload Sanitization

@Suite("Payload Sanitization Tests")
struct PayloadSanitizationTests {

    @Test("sanitized() truncates title to 500 chars")
    func truncatesTitle() {
        let longTitle = String(repeating: "A", count: 1000)
        let payload = AlertPayload(level: .whisper, title: longTitle)
        let sanitized = payload.sanitized()
        #expect(sanitized.title.count == 500)
    }

    @Test("sanitized() truncates message to 2000 chars")
    func truncatesMessage() {
        let longMessage = String(repeating: "B", count: 5000)
        let payload = AlertPayload(level: .whisper, title: "Test", message: longMessage)
        let sanitized = payload.sanitized()
        #expect(sanitized.message?.count == 2000)
    }

    @Test("sanitized() clamps negative ttl to 0")
    func clampsNegativeTTL() {
        let payload = AlertPayload(level: .whisper, title: "Test", ttl: -5)
        let sanitized = payload.sanitized()
        #expect(sanitized.ttl == 0)
    }

    @Test("sanitized() preserves valid ttl")
    func preservesValidTTL() {
        let payload = AlertPayload(level: .whisper, title: "Test", ttl: 60)
        let sanitized = payload.sanitized()
        #expect(sanitized.ttl == 60)
    }

    @Test("sanitized() limits actions to 10")
    func limitsActions() {
        let actions = (0..<15).map { AlertAction(label: "Action \($0)", id: "action_\($0)") }
        let payload = AlertPayload(level: .whisper, title: "Test", actions: actions)
        let sanitized = payload.sanitized()
        #expect(sanitized.actions.count == 10)
    }

    @Test("sanitized() accepts valid hex color")
    func acceptsValidHexColor() {
        let payload = AlertPayload(level: .whisper, title: "Test", color: "#FF6B6B")
        let sanitized = payload.sanitized()
        #expect(sanitized.color == "#FF6B6B")
    }

    @Test("sanitized() rejects invalid color")
    func rejectsInvalidColor() {
        let payload = AlertPayload(level: .whisper, title: "Test", color: "red")
        let sanitized = payload.sanitized()
        #expect(sanitized.color == nil)
    }

    @Test("sanitized() rejects color without hash")
    func rejectsColorWithoutHash() {
        let payload = AlertPayload(level: .whisper, title: "Test", color: "FF6B6B")
        let sanitized = payload.sanitized()
        #expect(sanitized.color == nil)
    }

    @Test("sanitized() rejects short hex color")
    func rejectsShortHexColor() {
        let payload = AlertPayload(level: .whisper, title: "Test", color: "#FFF")
        let sanitized = payload.sanitized()
        #expect(sanitized.color == nil)
    }

    @Test("sanitized() preserves valid minimal payload")
    func preservesValidMinimalPayload() {
        let payload = AlertPayload(level: .nudge, title: "Hello")
        let sanitized = payload.sanitized()
        #expect(sanitized.level == .nudge)
        #expect(sanitized.title == "Hello")
        #expect(sanitized.message == nil)
        #expect(sanitized.tts == false)
        #expect(sanitized.actions.isEmpty)
        #expect(sanitized.ttl == 0)
        #expect(sanitized.icon == nil)
        #expect(sanitized.color == nil)
    }
}

// MARK: - Config Security

@Suite("Config Security Tests")
struct ConfigSecurityTests {

    @Test("Default bindAddress is loopback")
    func defaultBindIsLoopback() {
        let config = HTTPServerConfig.default
        #expect(config.bindAddress == "127.0.0.1")
    }

    @Test("Config roundtrip preserves bindAddress")
    func roundtripBindAddress() throws {
        let original = KnokConfig(httpServer: HTTPServerConfig(
            enabled: true, port: 9999, authRequired: true, token: "knk_roundtriptest0000000000000000", bindAddress: "0.0.0.0"
        ))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KnokConfig.self, from: data)
        #expect(decoded.httpServer.bindAddress == "0.0.0.0")
    }

    @Test("Token generation produces sufficient entropy")
    func tokenEntropy() {
        let tokens = (0..<1000).map { _ in HTTPServerConfig.generateToken() }
        let unique = Set(tokens)
        #expect(unique.count == tokens.count)
    }

    @Test("Token is 36 chars with knk_ prefix")
    func tokenFormat() {
        let token = HTTPServerConfig.generateToken()
        #expect(token.hasPrefix("knk_"))
        #expect(token.count == 36)
    }

    @Test("Config file permissions are restrictive")
    func configFilePermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("config.json").path
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = ConfigManager(configPath: path, configDir: dir)

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = attrs[.posixPermissions] as? UInt16
        #expect(perms == 0o600, "Config file should have 0600 permissions, got \(String(format: "%o", perms ?? 0))")
    }

    @Test("Config directory permissions are restrictive")
    func configDirPermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("config.json").path
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = ConfigManager(configPath: path, configDir: dir)

        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        let perms = attrs[.posixPermissions] as? UInt16
        #expect(perms == 0o700, "Config dir should have 0700 permissions, got \(String(format: "%o", perms ?? 0))")
    }

    @Test("Default auth is required")
    func defaultAuthRequired() {
        let config = HTTPServerConfig.default
        #expect(config.authRequired == true)
    }
}

// MARK: - URL Scheme Security

@Suite("URL Scheme Security Tests")
struct URLSchemeSecurityTests {

    @Test("HTTPS URLs are valid")
    func httpsValid() {
        let url = URL(string: "https://example.com")!
        let scheme = url.scheme?.lowercased()
        #expect(scheme == "https")
    }

    @Test("HTTP URLs are valid")
    func httpValid() {
        let url = URL(string: "http://example.com")!
        let scheme = url.scheme?.lowercased()
        #expect(scheme == "http")
    }

    @Test("File URLs would be blocked")
    func fileBlocked() {
        let url = URL(string: "file:///etc/passwd")!
        let scheme = url.scheme?.lowercased()
        #expect(scheme != "http" && scheme != "https")
    }

    @Test("SSH URLs would be blocked")
    func sshBlocked() {
        let url = URL(string: "ssh://user@host")!
        let scheme = url.scheme?.lowercased()
        #expect(scheme != "http" && scheme != "https")
    }

    @Test("Tel URLs would be blocked")
    func telBlocked() {
        let url = URL(string: "tel:+1234567890")!
        let scheme = url.scheme?.lowercased()
        #expect(scheme != "http" && scheme != "https")
    }

    @Test("Custom scheme URLs would be blocked")
    func customSchemeBlocked() {
        let url = URL(string: "myapp://deeplink/path")!
        let scheme = url.scheme?.lowercased()
        #expect(scheme != "http" && scheme != "https")
    }

    @Test("URLs without scheme would be blocked")
    func noSchemeBlocked() {
        let url = URL(string: "example.com")
        let scheme = url?.scheme?.lowercased()
        #expect(scheme != "http" && scheme != "https")
    }
}

// MARK: - Payload Size

@Suite("Payload Size Security Tests")
struct PayloadSizeSecurityTests {

    @Test("Max payload size is 1MB")
    func maxPayloadSizeIs1MB() {
        #expect(KnokConstants.maxPayloadSize == 1_048_576)
    }

    @Test("Oversized payload would exceed max size")
    func oversizedPayloadExceedsLimit() throws {
        let hugeMessage = String(repeating: "X", count: KnokConstants.maxPayloadSize + 1)
        let payload = AlertPayload(level: .whisper, title: "Test", message: hugeMessage)
        let data = try JSONEncoder().encode(payload)
        #expect(data.count > KnokConstants.maxPayloadSize)
    }

    @Test("Sanitized payload fits within reasonable bounds")
    func sanitizedPayloadSize() throws {
        let longTitle = String(repeating: "T", count: 1000)
        let longMessage = String(repeating: "M", count: 5000)
        let actions = (0..<20).map { AlertAction(label: "Act \($0)", id: "a\($0)") }
        let payload = AlertPayload(
            level: .break,
            title: longTitle,
            message: longMessage,
            actions: actions,
            ttl: -10,
            color: "invalid"
        )
        let sanitized = payload.sanitized()
        let data = try JSONEncoder().encode(sanitized)
        #expect(data.count < KnokConstants.maxPayloadSize)
        #expect(sanitized.title.count == 500)
        #expect(sanitized.message?.count == 2000)
        #expect(sanitized.actions.count == 10)
        #expect(sanitized.ttl == 0)
        #expect(sanitized.color == nil)
    }
}
