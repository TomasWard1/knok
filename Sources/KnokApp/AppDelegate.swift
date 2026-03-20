import AppKit
import SwiftUI
import KnokCore
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var socketServer: SocketServer?
    private var httpServer: HTTPServer?
    let alertEngine = AlertEngine()
    let settings = AppSettings()
    let configManager = ConfigManager()
    let cliInstaller = CLIInstaller()
    let gitHubService = GitHubService()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    private var settingsWindow: NSWindow?
    private var gitHubPoller: GitHubPoller?

    @MainActor var alertHistory: AlertHistory { alertEngine.history }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire settings into alert engine
        alertEngine.settings = settings

        // Ensure socket directory exists
        let socketDir = KnokConstants.socketDir
        try? FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        // Start socket server
        socketServer = SocketServer(alertEngine: alertEngine)
        socketServer?.start()

        // Start HTTP server
        httpServer = HTTPServer(alertEngine: alertEngine, configManager: configManager)
        httpServer?.start()

        // Initialize GitHub integration
        gitHubService.initialize()
        if gitHubService.isConnected {
            gitHubPoller = GitHubPoller(service: gitHubService, alertEngine: alertEngine)
            gitHubPoller?.start()
        }
    }

    func restartHTTPServer() {
        httpServer?.restart()
    }

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            settings: settings,
            configManager: configManager,
            gitHubService: gitHubService,
            onHTTPRestart: { [weak self] in
                self?.restartHTTPServer()
            }
        )
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Knok Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 420))
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
        httpServer?.stop()
        gitHubPoller?.stop()
        try? FileManager.default.removeItem(atPath: KnokConstants.socketPath)
    }
}
