import Testing
import Foundation
@testable import KnokCore

@Suite("AlertPayload Tests")
struct AlertPayloadTests {

    @Test("Encode minimal payload")
    func encodeMinimal() throws {
        let payload = AlertPayload(level: .whisper, title: "Test")
        let data = try JSONEncoder().encode(payload)
        let json = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        #expect(json["level"]?.stringValue == "whisper")
        #expect(json["title"]?.stringValue == "Test")
        #expect(json["tts"]?.boolValue == false)
        #expect(json["ttl"]?.intValue == 0)
    }

    @Test("Encode full payload")
    func encodeFull() throws {
        let payload = AlertPayload(
            level: .break,
            title: "Production Down",
            message: "API returning 500s",
            tts: true,
            actions: [
                AlertAction(label: "Rollback", id: "rollback"),
                AlertAction(label: "Ignore", id: "ignore"),
            ],
            ttl: 60
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AlertPayload.self, from: data)
        #expect(decoded.level == .break)
        #expect(decoded.title == "Production Down")
        #expect(decoded.message == "API returning 500s")
        #expect(decoded.tts == true)
        #expect(decoded.actions.count == 2)
        #expect(decoded.actions[0].label == "Rollback")
        #expect(decoded.actions[0].id == "rollback")
        #expect(decoded.ttl == 60)
    }

    @Test("Roundtrip all levels")
    func roundtripLevels() throws {
        for level in AlertLevel.allCases {
            let payload = AlertPayload(level: level, title: "Test \(level.rawValue)")
            let data = try JSONEncoder().encode(payload)
            let decoded = try JSONDecoder().decode(AlertPayload.self, from: data)
            #expect(decoded.level == level)
        }
    }

    @Test("Decode from JSON string")
    func decodeFromJSON() throws {
        let json = """
        {"level":"knock","title":"Meeting","message":"In 5 minutes","tts":true,"actions":[{"label":"OK","id":"ok"}],"ttl":300}
        """
        let data = json.data(using: .utf8)!
        let payload = try JSONDecoder().decode(AlertPayload.self, from: data)
        #expect(payload.level == .knock)
        #expect(payload.title == "Meeting")
        #expect(payload.message == "In 5 minutes")
        #expect(payload.tts == true)
        #expect(payload.actions.count == 1)
        #expect(payload.ttl == 300)
    }

    @Test("Encode and decode with icon and color")
    func encodeDecodeIconColor() throws {
        let payload = AlertPayload(
            level: .nudge,
            title: "Deploy",
            icon: "bolt.fill",
            color: "#A855F7"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AlertPayload.self, from: data)
        #expect(decoded.icon == "bolt.fill")
        #expect(decoded.color == "#A855F7")
    }

    @Test("Decode with all optional fields missing")
    func decodeMinimalJSON() throws {
        let json = """
        {"level":"whisper","title":"Hello"}
        """
        let data = json.data(using: .utf8)!
        let payload = try JSONDecoder().decode(AlertPayload.self, from: data)
        #expect(payload.level == .whisper)
        #expect(payload.title == "Hello")
        #expect(payload.message == nil)
        #expect(payload.tts == false)
        #expect(payload.actions.isEmpty)
        #expect(payload.ttl == 0)
        #expect(payload.icon == nil)
        #expect(payload.color == nil)
    }

    @Test("Roundtrip preserves all fields")
    func roundtripAllFields() throws {
        let payload = AlertPayload(
            level: .break,
            title: "Critical",
            message: "Server down",
            tts: true,
            actions: [
                AlertAction(label: "View PR", id: "view-pr", url: "https://github.com/foo/bar/pull/1", icon: "link"),
                AlertAction(label: "Dismiss", id: "dismiss"),
            ],
            ttl: 120,
            icon: "exclamationmark.triangle.fill",
            color: "#FF6B6B"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AlertPayload.self, from: data)
        #expect(decoded.level == .break)
        #expect(decoded.title == "Critical")
        #expect(decoded.message == "Server down")
        #expect(decoded.tts == true)
        #expect(decoded.actions.count == 2)
        #expect(decoded.actions[0].label == "View PR")
        #expect(decoded.actions[0].id == "view-pr")
        #expect(decoded.actions[0].url == "https://github.com/foo/bar/pull/1")
        #expect(decoded.actions[0].icon == "link")
        #expect(decoded.actions[1].label == "Dismiss")
        #expect(decoded.actions[1].id == "dismiss")
        #expect(decoded.actions[1].url == nil)
        #expect(decoded.actions[1].icon == nil)
        #expect(decoded.ttl == 120)
        #expect(decoded.icon == "exclamationmark.triangle.fill")
        #expect(decoded.color == "#FF6B6B")
    }
}

// Helper for flexible JSON decoding in tests
struct AnyCodable: Codable {
    let value: Any

    var stringValue: String? { value as? String }
    var boolValue: Bool? { value as? Bool }
    var intValue: Int? { value as? Int }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else { value = "unknown" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else if let int = value as? Int { try container.encode(int) }
        else if let double = value as? Double { try container.encode(double) }
    }
}
