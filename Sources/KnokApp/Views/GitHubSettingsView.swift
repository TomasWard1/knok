import SwiftUI
import KnokCore

struct GitHubSettingsView: View {
    @ObservedObject var service: GitHubService

    @State private var searchText = ""

    var body: some View {
        Group {
            if service.isAuthenticating {
                authenticatingView
            } else if service.isConnected {
                connectedView
            } else {
                disconnectedView
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Connect to GitHub")
                .font(.title2.bold())

            Text("Monitor your repositories for PR status changes and CI results.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Connect with GitHub") {
                service.startDeviceFlow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Authenticating

    private var authenticatingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(0.8)

            Text("Enter this code on GitHub")
                .font(.headline)

            if !service.userCode.isEmpty {
                Text(service.userCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
            }

            HStack(spacing: 12) {
                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(service.userCode, forType: .string)
                }
                .buttonStyle(.bordered)

                if !service.verificationURL.isEmpty,
                   let url = URL(string: service.verificationURL) {
                    Button("Open GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button("Cancel") {
                service.cancelDeviceFlow()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Connected

    private var connectedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Profile header
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.username)
                            .font(.headline)
                        Text("Connected to GitHub")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Disconnect") {
                        service.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                .padding(.bottom, 4)

                Divider()

                // Repositories
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repositories")
                        .font(.headline)

                    TextField("Search repos...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    let filtered = filteredRepos
                    if filtered.isEmpty {
                        Text("No repositories found")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filtered, id: \.id) { repo in
                                repoRow(repo)
                            }
                        }
                    }
                }

                Divider()

                // Notifications
                notificationsSection
            }
            .padding()
        }
    }

    private var filteredRepos: [GitHubRepo] {
        if searchText.isEmpty { return service.repos }
        return service.repos.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    private func repoRow(_ repo: GitHubRepo) -> some View {
        let enabled = service.isRepoEnabled(repo)
        return Toggle(isOn: Binding(
            get: { enabled },
            set: { service.toggleRepo(repo, enabled: $0) }
        )) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(repo.fullName)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 2)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.headline)

            Toggle("PR Ready to Merge", isOn: Binding(
                get: { globalNotificationPref(\.prReadyToMerge) },
                set: { setGlobalNotificationPref(\.prReadyToMerge, value: $0) }
            ))

            Toggle("CI Failures on PRs", isOn: Binding(
                get: { globalNotificationPref(\.ciFailure) },
                set: { setGlobalNotificationPref(\.ciFailure, value: $0) }
            ))
        }
    }

    private func globalNotificationPref(_ keyPath: KeyPath<NotificationPreferences, Bool>) -> Bool {
        guard let cfg = service.config else { return true }
        let enabledRepos = cfg.repos.filter { $0.enabled }
        if enabledRepos.isEmpty { return true }
        return enabledRepos.allSatisfy { $0.notifications[keyPath: keyPath] }
    }

    private func setGlobalNotificationPref(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>, value: Bool) {
        guard var cfg = service.config else { return }
        for i in cfg.repos.indices {
            cfg.repos[i].notifications[keyPath: keyPath] = value
        }
        service.updateRepos(cfg.repos)
    }
}
