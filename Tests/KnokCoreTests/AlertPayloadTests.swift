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
