import Foundation
import AppKit

@MainActor
final class CLIInstaller: ObservableObject {
    @Published private(set) var isCLIInstalled = false
    @Published private(set) var isMCPInstalled = false

    static let installDir = "/usr/local/bin"
    static let cliLinkPath = "/usr/local/bin/knok"
    static let mcpLinkPath = "/usr/local/bin/knok-mcp"

    var isFullyInstalled: Bool { isCLIInstalled && isMCPInstalled }

    init() {
        checkInstallation()
    }

    func checkInstallation() {
        isCLIInstalled = Self.isSymlinkValid(at: Self.cliLinkPath, expectedBinary: "knok-cli")
        isMCPInstalled = Self.isSymlinkValid(at: Self.mcpLinkPath, expectedBinary: "knok-mcp")
    }

    func install() {
        guard let appBundle = Bundle.main.executableURL?.deletingLastPathComponent() else { return }
        let cliSource = appBundle.appendingPathComponent("knok-cli").path
        let mcpSource = appBundle.appendingPathComponent("knok-mcp").path

        var commands: [String] = []

        // Ensure /usr/local/bin exists
        commands.append("mkdir -p \(Self.installDir)")

        if !isCLIInstalled && FileManager.default.fileExists(atPath: cliSource) {
            let escaped = cliSource.replacingOccurrences(of: "'", with: "'\\''")
            commands.append("ln -sf '\(escaped)' '\(Self.cliLinkPath)'")
        }
        if !isMCPInstalled && FileManager.default.fileExists(atPath: mcpSource) {
            let escaped = mcpSource.replacingOccurrences(of: "'", with: "'\\''")
            commands.append("ln -sf '\(escaped)' '\(Self.mcpLinkPath)'")
        }

        guard !commands.isEmpty else { return }

        let script = commands.joined(separator: " && ")

        // Try without privileges first, escalate if needed
        if tryRun(script) || tryRunPrivileged(script) {
            checkInstallation()
        }
    }

    // MARK: - Private

    private static func isSymlinkValid(at path: String, expectedBinary: String) -> Bool {
        let fm = FileManager.default
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: path) else { return false }
        // Check that symlink points to something inside a Knok.app bundle
        return dest.contains("Knok.app/Contents/MacOS/\(expectedBinary)")
            && fm.fileExists(atPath: dest)
    }

    private func tryRun(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func tryRunPrivileged(_ script: String) -> Bool {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        guard let scriptObj = NSAppleScript(source: appleScript) else { return false }
        var error: NSDictionary?
        scriptObj.executeAndReturnError(&error)
        return error == nil
    }
}
