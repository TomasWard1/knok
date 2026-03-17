import SwiftUI

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("defaultTTSEnabled") private var defaultTTSEnabled = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Section("Text-to-Speech") {
                Toggle("Enable TTS by default", isOn: $defaultTTSEnabled)
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Socket", value: "~/.knok/knok.sock")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
