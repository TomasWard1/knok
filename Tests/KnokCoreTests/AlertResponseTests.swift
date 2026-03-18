import Testing
import Foundation
@testable import KnokCore

@Suite("AlertResponse Tests")
struct AlertResponseTests {

    @Test("Dismissed response")
    func dismissed() throws {
        let response = AlertResponse.dismissed
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AlertResponse.self, from: data)
        #expect(decoded.action == "dismissed")
    }

    @Test("Timeout response")
    func timeout() throws {
        let response = AlertResponse.timeout
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AlertResponse.self, from: data)
        #expect(decoded.action == "timeout")
    }

    @Test("Button clicked response")
    func buttonClicked() throws {
        let response = AlertResponse.buttonClicked("rollback")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AlertResponse.self, from: data)
        #expect(decoded.action == "rollback")
    }

    @Test("Decode from JSON")
    func decodeFromJSON() throws {
        let json = """
        {"action":"custom_action"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AlertResponse.self, from: data)
        #expect(response.action == "custom_action")
    }

    // MARK: - Serialization format

    @Test("Dismissed serializes with correct action key")
    func dismissedJSON() throws {
        let response = AlertResponse.dismissed
        let data = try JSONEncoder().encode(response)
        let json = try JSONDecoder().decode([String: String].self, from: data)
        #expect(json == ["action": "dismissed"])
    }

    @Test("Timeout serializes with correct action key")
    func timeoutJSON() throws {
        let response = AlertResponse.timeout
        let data = try JSONEncoder().encode(response)
        let json = try JSONDecoder().decode([String: String].self, from: data)
        #expect(json == ["action": "timeout"])
    }

    @Test("Button clicked serializes with button id as action")
    func buttonClickedJSON() throws {
        let response = AlertResponse.buttonClicked("deploy-now")
        let data = try JSONEncoder().encode(response)
        let json = try JSONDecoder().decode([String: String].self, from: data)
        #expect(json == ["action": "deploy-now"])
    }

    // MARK: - Edge cases

    @Test("Decode fails when action key is missing")
    func missingActionFails() throws {
        let json = """
        {"status":"ok"}
        """
        let data = json.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AlertResponse.self, from: data)
        }
    }

    @Test("Empty action string is valid")
    func emptyActionString() throws {
        let json = """
        {"action":""}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AlertResponse.self, from: data)
        #expect(response.action == "")
    }

    @Test("Action with special characters")
    func specialCharacters() throws {
        let response = AlertResponse.buttonClicked("btn-123_test.action")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AlertResponse.self, from: data)
        #expect(decoded.action == "btn-123_test.action")
    }
}
