import Testing
import Foundation
@testable import KnokCore

@Suite("AlertAction Tests")
struct AlertActionTests {

    @Test("Encode and decode with url and icon")
    func encodeDecodeUrlIcon() throws {
        let action = AlertAction(label: "View PR", id: "view-pr", url: "https://github.com/foo/bar/pull/1", icon: "link")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AlertAction.self, from: data)
        #expect(decoded.label == "View PR")
        #expect(decoded.id == "view-pr")
        #expect(decoded.url == "https://github.com/foo/bar/pull/1")
        #expect(decoded.icon == "link")
    }

    @Test("Decode with only label and id")
    func decodeMinimal() throws {
        let json = """
        {"label":"OK","id":"ok"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AlertAction.self, from: data)
        #expect(decoded.label == "OK")
        #expect(decoded.id == "ok")
        #expect(decoded.url == nil)
        #expect(decoded.icon == nil)
    }

    @Test("Roundtrip preserves all fields")
    func roundtripAll() throws {
        let action = AlertAction(label: "Deploy", id: "deploy", url: "https://example.com/deploy", icon: "bolt.fill")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AlertAction.self, from: data)
        #expect(decoded.label == action.label)
        #expect(decoded.id == action.id)
        #expect(decoded.url == action.url)
        #expect(decoded.icon == action.icon)
    }
}
