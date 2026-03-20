import SwiftUI
import KnokCore
import Sparkle

@main
struct KnokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Knok", image: "MenuBarIcon") {
            MenuBarView(
                history: appDelegate.alertHistory,
                cliInstaller: appDelegate.cliInstaller,
                updater: appDelegate.updaterController.updater,
                onOpenSettings: { appDelegate.openSettings() }
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: appDelegate.settings, configManager: appDelegate.configManager, onHTTPRestart: { appDelegate.restartHTTPServer() })
        }
    }
}
