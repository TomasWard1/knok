import AppKit
import SwiftUI
import KnokCore
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var socketServer: SocketServer?
    let alertEngine = AlertEngine()
    let settings = AppSettings()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    @MainActor var alertHistory: AlertHistory { alertEngine.history }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Wire settings into alert engine
        Task { @MainActor in
            alertEngine.settings = settings
        }

        // Set up menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let menuIcon = NSImage(named: "MenuBarIcon")
            menuIcon?.isTemplate = true
            button.image = menuIcon
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Set up popover with MenuBarView
        Task { @MainActor in
            let menuBarView = MenuBarView(history: alertEngine.history, updater: updaterController.updater, onOpenSettings: { [weak self] in
                self?.openSettings()
            })
            popover.contentSize = NSSize(width: 320, height: 380)
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: menuBarView)
        }

        // Ensure socket directory exists
        let socketDir = KnokConstants.socketDir
        try? FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true)

        // Start socket server
        socketServer = SocketServer(alertEngine: alertEngine)
        socketServer?.start()
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func openSettings() {
        popover.performClose(nil)

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

    // Prevent app from quitting when last window closes
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        // Clean up socket file
        try? FileManager.default.removeItem(atPath: KnokConstants.socketPath)
    }
}
