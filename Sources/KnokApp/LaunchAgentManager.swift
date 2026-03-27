import Foundation
import os.log

@MainActor
enum LaunchAgentManager {
    private static let logger = Logger(subsystem: "app.getknok.Knok", category: "LaunchAgent")
    private static let plistName = "app.getknok.Knok.plist"

    private static var destinationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(plistName)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: destinationURL.path)
    }

    static func install() {
        guard let bundledURL = Bundle.main.url(forResource: "app.getknok.Knok", withExtension: "plist") else {
            logger.error("LaunchAgent plist not found in bundle")
            return
        }

        let destDir = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create LaunchAgents directory: \(error.localizedDescription)")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: bundledURL, to: destinationURL)
            logger.info("LaunchAgent plist installed")
        } catch {
            logger.error("Failed to copy LaunchAgent plist: \(error.localizedDescription)")
            return
        }

        runLaunchctl(["load", destinationURL.path])
    }

    static func uninstall() {
        let path = destinationURL.path
        if FileManager.default.fileExists(atPath: path) {
            runLaunchctl(["unload", path])
            do {
                try FileManager.default.removeItem(atPath: path)
                logger.info("LaunchAgent plist removed")
            } catch {
                logger.error("Failed to remove LaunchAgent plist: \(error.localizedDescription)")
            }
        }
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                logger.warning("launchctl \(arguments.joined(separator: " ")) exited with status \(process.terminationStatus)")
            }
        } catch {
            logger.error("Failed to run launchctl: \(error.localizedDescription)")
        }
    }
}
