import Testing
import Foundation
@testable import KnokCore

@Suite("KnokError Tests")
struct KnokErrorTests {

    @Test("socketCreationFailed has description")
    func socketCreationFailed() {
        let error = KnokError.socketCreationFailed(errno: EACCES)
        #expect(error.localizedDescription.contains("Failed to create socket"))
    }

    @Test("socketPathTooLong has description")
    func socketPathTooLong() {
        let error = KnokError.socketPathTooLong
        #expect(error.localizedDescription == "Socket path exceeds maximum length")
    }

    @Test("connectionFailed with ECONNREFUSED mentions app not running")
    func connectionRefused() {
        let error = KnokError.connectionFailed(errno: ECONNREFUSED)
        #expect(error.localizedDescription.contains("not running"))
    }

    @Test("connectionFailed with ENOENT mentions app not running")
    func connectionNoEntry() {
        let error = KnokError.connectionFailed(errno: ENOENT)
        #expect(error.localizedDescription.contains("not running"))
    }

    @Test("connectionFailed with other errno gives generic message")
    func connectionOtherError() {
        let error = KnokError.connectionFailed(errno: ETIMEDOUT)
        #expect(error.localizedDescription.contains("Failed to connect"))
    }

    @Test("sendFailed has description")
    func sendFailed() {
        let error = KnokError.sendFailed(errno: EPIPE)
        #expect(error.localizedDescription.contains("Failed to send data"))
    }

    @Test("receiveFailed has description")
    func receiveFailed() {
        let error = KnokError.receiveFailed(errno: ECONNRESET)
        #expect(error.localizedDescription.contains("Failed to receive response"))
    }

    @Test("appNotRunning has description")
    func appNotRunning() {
        let error = KnokError.appNotRunning
        #expect(error.localizedDescription.contains("not running"))
    }

    @Test("invalidResponse has description")
    func invalidResponse() {
        let error = KnokError.invalidResponse
        #expect(error.localizedDescription == "Invalid response from Knok app")
    }

    @Test("timeout has description")
    func timeout() {
        let error = KnokError.timeout
        #expect(error.localizedDescription == "Timed out waiting for response")
    }

    @Test("All errors conform to LocalizedError")
    func conformsToLocalizedError() {
        let errors: [KnokError] = [
            .socketCreationFailed(errno: 0),
            .socketPathTooLong,
            .connectionFailed(errno: 0),
            .sendFailed(errno: 0),
            .receiveFailed(errno: 0),
            .appNotRunning,
            .invalidResponse,
            .timeout,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.localizedDescription.isEmpty)
        }
    }
}
