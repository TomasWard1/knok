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
}
