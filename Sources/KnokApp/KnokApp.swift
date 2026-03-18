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
                updater: appDelegate.updaterController.updater,
                onOpenSettings: { appDelegate.openSettings() }
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: appDelegate.settings)
        }
    }
}
