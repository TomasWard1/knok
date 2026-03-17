import SwiftUI
import KnokCore

@main
struct KnokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Knok", systemImage: "bell.badge") {
            MenuBarView(history: appDelegate.alertHistory, updater: appDelegate.updaterController.updater)
        }
        Settings {
            SettingsView(settings: appDelegate.settings)
        }
    }
}
