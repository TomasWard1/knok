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

    // MARK: - Invalid JSON

    @Test("Decode fails when label is missing")
    func missingLabelFails() throws {
        let json = """
        {"id": "ok"}
        """
        let data = json.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AlertAction.self, from: data)
        }
    }

    @Test("Decode fails when id is missing")
    func missingIdFails() throws {
        let json = """
        {"label": "OK"}
        """
        let data = json.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AlertAction.self, from: data)
        }
    }

    // MARK: - Hashable

    @Test("Equal actions have same hash")
    func hashableEquality() {
        let a = AlertAction(label: "OK", id: "ok", url: nil, icon: nil)
        let b = AlertAction(label: "OK", id: "ok", url: nil, icon: nil)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different actions are not equal")
    func hashableInequality() {
        let a = AlertAction(label: "OK", id: "ok")
        let b = AlertAction(label: "Cancel", id: "cancel")
        #expect(a != b)
    }

    @Test("Actions can be used in a Set")
    func usableInSet() {
        let a = AlertAction(label: "OK", id: "ok")
        let b = AlertAction(label: "OK", id: "ok")
        let c = AlertAction(label: "Cancel", id: "cancel")
        let set: Set<AlertAction> = [a, b, c]
        #expect(set.count == 2)
    }

    // MARK: - Init with url and icon

    @Test("Init with url only")
    func initWithUrl() {
        let action = AlertAction(label: "Open", id: "open", url: "https://example.com")
        #expect(action.url == "https://example.com")
        #expect(action.icon == nil)
    }

    @Test("Init with icon only")
    func initWithIcon() {
        let action = AlertAction(label: "Star", id: "star", icon: "star.fill")
        #expect(action.url == nil)
        #expect(action.icon == "star.fill")
    }
}
