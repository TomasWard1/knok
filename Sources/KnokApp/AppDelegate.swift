import AppKit
import SwiftUI
import KnokCore
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var socketServer: SocketServer?
    let alertEngine = AlertEngine()
    let settings = AppSettings()
    let cliInstaller = CLIInstaller()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    private var settingsWindow: NSWindow?

    @MainActor var alertHistory: AlertHistory { alertEngine.history }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire settings into alert engine
        alertEngine.settings = settings

        // Ensure socket directory exists
        let socketDir = KnokConstants.socketDir
        try? FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true)

        // Start socket server
        socketServer = SocketServer(alertEngine: alertEngine)
        socketServer?.start()
    }

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settings)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Knok Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 500))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        try? FileManager.default.removeItem(atPath: KnokConstants.socketPath)
    }
}
