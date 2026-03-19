import SwiftUI
import KnokCore
import Sparkle

struct MenuBarView: View {
    @ObservedObject var history: AlertHistory
    @ObservedObject var cliInstaller: CLIInstaller
    var updater: SPUUpdater?
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Knok")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                if !history.items.isEmpty {
                    Text("\(history.items.count)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
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
                    .font(.system(size: 14, design: .rounded))
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
                    MenuRow("Clear History") {
                        history.clear()
                    }

                    Divider()
                }

                if !cliInstaller.isFullyInstalled {
                    MenuRow("Install CLI Tools...", icon: "arrow.down.circle") {
                        cliInstaller.install()
                    }

                    Divider()
                }

                MenuRow("Check for Updates...") {
                    updater?.checkForUpdates()
                }

                Divider()

                MenuRow("Settings...") {
                    onOpenSettings?()
                }

                MenuRow("Quit Knok") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 300)
    }
}

// MARK: - Menu Row (highlight on hover like native NSMenu)

private struct MenuRow: View {
    let title: String
    let icon: String?
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: 14, design: .rounded))
            }
            .foregroundStyle(isHovered ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
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
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            // Title + level
            VStack(alignment: .leading, spacing: 2) {
                Text(item.payload.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.payload.level.rawValue)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.tertiary)

                    if let response = item.response {
                        Text("· \(response.action)")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Relative timestamp
            Text(relativeTime(item.timestamp))
                .font(.system(size: 14, design: .rounded))
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
