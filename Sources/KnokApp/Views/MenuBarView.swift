import SwiftUI
import KnokCore

struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Knok")
                .font(.headline)

            Divider()

            Text("No recent alerts")
                .foregroundStyle(.secondary)
                .font(.caption)

            Divider()

            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit Knok") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(width: 200)
    }
}
