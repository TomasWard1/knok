import Testing
import Foundation
@testable import KnokCore

@Suite("AlertLevel Tests")
struct AlertLevelTests {

    @Test("All cases exist")
    func allCases() {
        #expect(AlertLevel.allCases.count == 4)
        #expect(AlertLevel.allCases.contains(.whisper))
        #expect(AlertLevel.allCases.contains(.nudge))
        #expect(AlertLevel.allCases.contains(.knock))
        #expect(AlertLevel.allCases.contains(.break))
    }

    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(AlertLevel.whisper.rawValue == "whisper")
        #expect(AlertLevel.nudge.rawValue == "nudge")
        #expect(AlertLevel.knock.rawValue == "knock")
        #expect(AlertLevel.break.rawValue == "break")
    }

    @Test("Init from raw value")
    func initFromRaw() {
        #expect(AlertLevel(rawValue: "whisper") == .whisper)
        #expect(AlertLevel(rawValue: "nudge") == .nudge)
        #expect(AlertLevel(rawValue: "knock") == .knock)
        #expect(AlertLevel(rawValue: "break") == .break)
        #expect(AlertLevel(rawValue: "invalid") == nil)
        #expect(AlertLevel(rawValue: "") == nil)
    }

    @Test("Encode each level to JSON")
    func encode() throws {
        let encoder = JSONEncoder()
        for level in AlertLevel.allCases {
            let data = try encoder.encode(level)
            let str = String(data: data, encoding: .utf8)!
            #expect(str == "\"\(level.rawValue)\"")
        }
    }

    @Test("Decode each level from JSON")
    func decode() throws {
        let decoder = JSONDecoder()
        for level in AlertLevel.allCases {
            let json = "\"\(level.rawValue)\"".data(using: .utf8)!
            let decoded = try decoder.decode(AlertLevel.self, from: json)
            #expect(decoded == level)
        }
    }

    @Test("Decode invalid level fails")
    func decodeInvalid() {
        let json = "\"panic\"".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AlertLevel.self, from: json)
        }
    }
}
