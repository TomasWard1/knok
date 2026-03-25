import SwiftUI
import KnokCore

// MARK: - Tailscale Helpers (file-scope to avoid @MainActor isolation)

private let tailscalePath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

private func runTailscale(_ args: [String]) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    let quoted = args.map { "'\($0)'" }.joined(separator: " ")
    process.arguments = ["-c", "\(tailscalePath) \(quoted)"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? pipe.fileHandleForReading.readDataToEndOfFile() : nil
    } catch {
        return nil
    }
}

struct GitHubSettingsView: View {
    @ObservedObject var service: GitHubService
    var webhookHandler: GitHubWebhookHandler?

    @State private var searchText = ""
    @State private var webhookSecretRevealed = false
    @State private var tailscaleDNS: String? = nil
    @State private var isTailscaleDetected = false
    @State private var isFunnelActive = false
    @State private var isEnablingFunnel = false
    @State private var funnelError: String? = nil

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
                // Account
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

                // Webhook Setup
                webhookSetupSection

                Divider()

                // Repositories
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repositories")
                        .font(.headline)

                    if !service.isAppInstalled {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Install the Knok GitHub App to access your repositories.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            HStack(spacing: 8) {
                                Button("Install on GitHub") {
                                    NSWorkspace.shared.open(service.installURL)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Refresh") {
                                    Task {
                                        await service.checkInstallation()
                                        if service.isAppInstalled {
                                            await service.fetchRepos()
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }

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
        .onAppear {
            detectTailscale()
        }
    }

    // MARK: - Webhook Setup

    private var webhookURL: String? {
        guard let dns = tailscaleDNS else { return nil }
        return "https://\(dns):443/github/webhook"
    }

    private var webhookSetupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Webhook Setup")
                    .font(.headline)
                Spacer()
                webhookStatusBadge
            }

            // Step 1: Tailscale Funnel
            stepRow(number: 1, title: "Tailscale Funnel", isDone: isFunnelActive) {
                if !isTailscaleDetected {
                    Label("Tailscale not found. Install Tailscale to receive GitHub webhooks.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if isFunnelActive {
                    if let url = webhookURL {
                        HStack(spacing: 4) {
                            Text(url)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .textSelection(.enabled)
                            copyButton(url)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Expose Knok's HTTP server to receive webhooks from GitHub.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                enableFunnel()
                            } label: {
                                if isEnablingFunnel {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 2)
                                }
                                Text(isEnablingFunnel ? "Enabling..." : "Enable Funnel")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isEnablingFunnel)

                            if let error = funnelError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            // Step 2: Webhook Secret
            stepRow(number: 2, title: "Secret", isDone: service.config?.webhookSecret != nil) {
                if let secret = service.config?.webhookSecret {
                    HStack(spacing: 4) {
                        if webhookSecretRevealed {
                            Text(secret)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                        } else {
                            Text(String(repeating: "\u{2022}", count: 24))
                                .font(.system(.caption, design: .monospaced))
                        }
                        Button { webhookSecretRevealed.toggle() } label: {
                            Image(systemName: webhookSecretRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        copyButton(secret)
                    }
                } else {
                    Button("Generate") {
                        generateWebhookSecret()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Webhook count
            if webhookSetupComplete {
                webhookCountIndicator
            }
        }
    }

    private var webhookSetupComplete: Bool {
        isFunnelActive && service.config?.webhookSecret != nil
    }

    private var webhookCountIndicator: some View {
        let total = service.config?.repos.filter(\.enabled).count ?? 0
        let withHooks = service.config?.repos.filter { $0.enabled && $0.webhookId != nil }.count ?? 0
        return HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(withHooks)/\(total) repos with active webhooks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Webhook UI Components

    private var webhookStatusBadge: some View {
        HStack(spacing: 5) {
            if let lastEvent = webhookHandler?.lastEventDate {
                let elapsed = Date().timeIntervalSince(lastEvent)
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(formatElapsed(elapsed) + " ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if service.config?.webhookSecret != nil && isFunnelActive {
                Circle().fill(.yellow).frame(width: 7, height: 7)
                Text("Waiting for events")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepRow<Content: View>(number: Int, title: String, isDone: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(isDone ? .green : .secondary)
                .font(.system(size: 16))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                content()
            }
        }
    }

    private func copyButton(_ value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    // MARK: - Helpers

    private func generateWebhookSecret() {
        let secret = GitHubConfig.generateWebhookSecret()
        service.updateWebhookSecret(secret)
        // Auto-sync webhooks if funnel already active
        if let url = webhookURL, isFunnelActive {
            Task {
                await service.syncWebhooks(webhookURL: url)
            }
        }
    }

    private func detectTailscale() {
        DispatchQueue.global().async {
            guard FileManager.default.fileExists(atPath: tailscalePath) else {
                DispatchQueue.main.async {
                    self.isTailscaleDetected = false
                }
                return
            }

            // Get DNS name
            let statusOut = runTailscale(["status", "--json"])
            if let data = statusOut,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let selfNode = json["Self"] as? [String: Any],
               let dnsName = selfNode["DNSName"] as? String {
                let cleanDNS = dnsName.hasSuffix(".") ? String(dnsName.dropLast()) : dnsName
                DispatchQueue.main.async {
                    self.tailscaleDNS = cleanDNS
                    self.isTailscaleDetected = true
                }
            } else {
                DispatchQueue.main.async {
                    self.isTailscaleDetected = false
                }
                return
            }

            // Check funnel status inline
            let funnelActive: Bool = {
                if let data = runTailscale(["funnel", "status", "--json"]),
                   let output = String(data: data, encoding: .utf8),
                   !output.isEmpty {
                    return output.contains("9999")
                }
                if let data = runTailscale(["funnel", "status"]),
                   let output = String(data: data, encoding: .utf8) {
                    return output.contains("9999")
                }
                return false
            }()
            DispatchQueue.main.async {
                self.isFunnelActive = funnelActive
            }
        }
    }

    private func enableFunnel() {
        isEnablingFunnel = true
        funnelError = nil

        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "\(tailscalePath) funnel --bg 9999"]
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.isFunnelActive = true
                        self.isEnablingFunnel = false
                        self.funnelError = nil
                        // Auto-sync webhooks if secret already set
                        if let url = self.webhookURL, self.service.config?.webhookSecret != nil {
                            Task {
                                await self.service.syncWebhooks(webhookURL: url)
                            }
                        }
                    }
                } else {
                    let msg = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        self.isEnablingFunnel = false
                        self.funnelError = msg.isEmpty ? "Funnel setup failed" : msg
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isEnablingFunnel = false
                    self.funnelError = error.localizedDescription
                }
            }
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h"
    }

    private var filteredRepos: [GitHubRepo] {
        if searchText.isEmpty { return service.repos }
        return service.repos.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    private func repoRow(_ repo: GitHubRepo) -> some View {
        let enabled = service.isRepoEnabled(repo)
        return Toggle(isOn: Binding(
            get: { enabled },
            set: { newValue in
                service.toggleRepo(repo, enabled: newValue)
                guard webhookSetupComplete, let url = webhookURL,
                      let secret = service.config?.webhookSecret else { return }
                Task {
                    if newValue {
                        let _ = await service.createRepoWebhook(
                            owner: repo.owner.login,
                            name: repo.name,
                            webhookURL: url,
                            secret: secret
                        )
                    } else {
                        let key = "\(repo.owner.login)/\(repo.name)"
                        if let hookId = service.config?.repos.first(where: { "\($0.owner)/\($0.name)" == key })?.webhookId {
                            let _ = await service.deleteRepoWebhook(
                                owner: repo.owner.login,
                                name: repo.name,
                                hookId: hookId
                            )
                        }
                    }
                }
            }
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

            Toggle("New PR Opened", isOn: Binding(
                get: { globalNotificationPref(\.prOpened) },
                set: { setGlobalNotificationPref(\.prOpened, value: $0) }
            ))

            Toggle("PR Merged", isOn: Binding(
                get: { globalNotificationPref(\.prMerged) },
                set: { setGlobalNotificationPref(\.prMerged, value: $0) }
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
