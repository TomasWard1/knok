import Testing
import Foundation
@testable import KnokCore

@Suite("KnokConstants Tests")
struct KnokConstantsTests {

    @Test("Socket path is under ~/.knok/")
    func socketPath() {
        #expect(KnokConstants.socketPath.hasSuffix("/.knok/knok.sock"))
    }

    @Test("Socket dir is under home directory")
    func socketDir() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(KnokConstants.socketDir.path.hasPrefix(home))
    }

    @Test("Version is semver format")
    func version() {
        let parts = KnokConstants.version.split(separator: ".")
        #expect(parts.count == 3)
        for part in parts {
            #expect(Int(part) != nil)
        }
    }

    @Test("App name is Knok")
    func appName() {
        #expect(KnokConstants.appName == "Knok")
    }

    @Test("Max payload size is 1MB")
    func maxPayloadSize() {
        #expect(KnokConstants.maxPayloadSize == 1_048_576)
    }

    @Test("Default timeout is 300 seconds")
    func defaultTimeout() {
        #expect(KnokConstants.defaultTimeout == 300)
    }
}
