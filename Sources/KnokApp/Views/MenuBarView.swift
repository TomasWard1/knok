import SwiftUI
import KnokCore
import Sparkle

struct MenuBarView: View {
    @ObservedObject var history: AlertHistory
    var updater: SPUUpdater?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Knok")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if !history.items.isEmpty {
                    Text("\(history.items.count)")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // Alert list or empty state
            if history.items.isEmpty {
                Text("No recent alerts")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(history.items) { item in
                            AlertRow(item: item)
                            if item.id != history.items.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Divider()

            // Footer actions
            VStack(spacing: 0) {
                if !history.items.isEmpty {
                    Button {
                        history.clear()
                    } label: {
                        Text("Clear History")
                            .font(.system(.caption, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    Divider()
                }

                Button {
                    updater?.checkForUpdates()
                } label: {
                    Text("Check for Updates...")
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Text("Settings...")
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .keyboardShortcut(",", modifiers: .command)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit Knok")
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 260)
    }
}

// MARK: - Alert Row

private struct AlertRow: View {
    let item: AlertHistoryItem

    var body: some View {
        HStack(spacing: 8) {
            // Accent dot
            Circle()
                .fill(item.payload.resolvedAccentColor())
                .frame(width: 6, height: 6)

            // Icon
            Image(systemName: item.payload.resolvedIcon())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            // Title + level
            VStack(alignment: .leading, spacing: 1) {
                Text(item.payload.title)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.payload.level.rawValue)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.tertiary)

                    if let response = item.response {
                        Text("-- \(response.action)")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Relative timestamp
            Text(relativeTime(item.timestamp))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}
