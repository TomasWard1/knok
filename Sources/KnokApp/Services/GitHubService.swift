import Foundation
import KnokCore
import os

private let logger = Logger(subsystem: "app.getknok.Knok", category: "GitHubService")

@MainActor
final class GitHubService: ObservableObject {
    // MARK: - Constants

    private let clientID = "Iv23lihJtKdAxKbAPC2N"
    private let accessTokenKey = "github_access_token"
    private let refreshTokenKey = "github_refresh_token"
    private let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".knok")
        return dir.appendingPathComponent("github.json")
    }()

    // MARK: - Published State

    @Published var isConnected = false
    @Published var username = ""
    @Published var isAuthenticating = false
    @Published var userCode = ""
    @Published var verificationURL = ""
    @Published var repos: [GitHubRepo] = []
    @Published var config: GitHubConfig?

    // MARK: - Private

    private var deviceCode = ""
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 5

    // MARK: - Init

    nonisolated init() {}

    // MARK: - Initialize

    func initialize() {
        loadConfig()
        if let _ = KeychainHelper.readString(key: accessTokenKey) {
            isConnected = true
            username = config?.username ?? ""
            logger.info("Initialized with stored token for \(self.username)")
            Task {
                await validateToken()
                await fetchRepos()
            }
        }
    }

    // MARK: - Token Validation

    /// Validates that the token can access private repos (GitHub App tokens
    /// don't use OAuth scopes — permissions come from the app config).
    private func validateToken() async {
        guard let data = await apiGet(path: "/user/repos?per_page=1&type=private") else {
            logger.error("Token validation failed — could not reach GitHub API")
            return
        }

        if let repos = try? JSONDecoder().decode([GitHubRepo].self, from: data) {
            logger.info("Token validation passed (private repo access: \(repos.count > 0 ? "yes" : "no visible private repos"))")
        } else {
            logger.warning("Token validation: unexpected response decoding repos")
        }
    }

    // MARK: - Device Flow OAuth

    func startDeviceFlow() {
        isAuthenticating = true
        userCode = ""
        verificationURL = ""

        Task {
            guard let url = URL(string: "https://github.com/login/device/code") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let body = "client_id=\(clientID)&scope=repo"
            request.httpBody = body.data(using: .utf8)

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: data)
                self.deviceCode = response.deviceCode
                self.userCode = response.userCode
                self.verificationURL = response.verificationUri
                self.pollInterval = TimeInterval(response.interval)
                logger.info("Device flow started, user code: \(response.userCode)")
                startPolling()
            } catch {
                logger.error("Device flow error: \(error.localizedDescription)")
                isAuthenticating = false
            }
        }
    }

    func cancelDeviceFlow() {
        pollTimer?.invalidate()
        pollTimer = nil
        isAuthenticating = false
        userCode = ""
        verificationURL = ""
        deviceCode = ""
        logger.info("Device flow cancelled")
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollForToken()
            }
        }
    }

    private func pollForToken() async {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)

            if let error = tokenResponse.error {
                if error == "authorization_pending" {
                    return // Keep polling
                } else if error == "slow_down" {
                    pollInterval += 5
                    startPolling()
                    return
                } else {
                    logger.warning("Device flow error response: \(error)")
                    cancelDeviceFlow()
                    return
                }
            }

            guard let accessToken = tokenResponse.accessToken else { return }

            // Store tokens
            KeychainHelper.saveString(key: accessTokenKey, value: accessToken)
            if let refreshToken = tokenResponse.refreshToken {
                KeychainHelper.saveString(key: refreshTokenKey, value: refreshToken)
            }

            // Fetch user info
            pollTimer?.invalidate()
            pollTimer = nil
            isAuthenticating = false

            if let userData = await apiGet(path: "/user"),
               let json = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
               let login = json["login"] as? String {
                username = login
            }

            config = GitHubConfig(username: username)
            saveConfig()
            isConnected = true
            logger.info("OAuth complete, connected as \(self.username)")

            await validateToken()
            await fetchRepos()
        } catch {
            logger.error("Token poll error: \(error.localizedDescription)")
        }
    }

    // MARK: - API

    func apiGet(path: String) async -> Data? {
        guard let token = KeychainHelper.readString(key: accessTokenKey),
              let url = URL(string: "https://api.github.com\(path)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    logger.warning("401 on \(path), attempting token refresh")
                    let refreshed = await refreshAccessToken()
                    if refreshed {
                        return await apiGet(path: path)
                    } else {
                        logger.error("Token refresh failed, disconnecting")
                        disconnect()
                        return nil
                    }
                }
                if httpResponse.statusCode != 200 {
                    logger.warning("HTTP \(httpResponse.statusCode) on \(path)")
                }
            }
            return data
        } catch {
            logger.error("API error for \(path): \(error.localizedDescription)")
            return nil
        }
    }

    func apiPost(path: String, body: Data) async -> Data? {
        guard let token = KeychainHelper.readString(key: accessTokenKey),
              let url = URL(string: "https://api.github.com\(path)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    logger.warning("401 on POST \(path), attempting token refresh")
                    let refreshed = await refreshAccessToken()
                    if refreshed {
                        return await apiPost(path: path, body: body)
                    } else {
                        logger.error("Token refresh failed, disconnecting")
                        disconnect()
                        return nil
                    }
                }
                if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    logger.warning("HTTP \(httpResponse.statusCode) on POST \(path): \(bodyStr)")
                    return nil
                }
            }
            return data
        } catch {
            logger.error("API POST error for \(path): \(error.localizedDescription)")
            return nil
        }
    }

    func apiDelete(path: String) async -> Bool {
        guard let token = KeychainHelper.readString(key: accessTokenKey),
              let url = URL(string: "https://api.github.com\(path)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    logger.warning("401 on DELETE \(path), attempting token refresh")
                    let refreshed = await refreshAccessToken()
                    if refreshed {
                        return await apiDelete(path: path)
                    } else {
                        logger.error("Token refresh failed, disconnecting")
                        disconnect()
                        return false
                    }
                }
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    return true
                }
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                logger.warning("HTTP \(httpResponse.statusCode) on DELETE \(path): \(bodyStr)")
                return false
            }
            return false
        } catch {
            logger.error("API DELETE error for \(path): \(error.localizedDescription)")
            return false
        }
    }

    private func refreshAccessToken() async -> Bool {
        guard let refreshToken = KeychainHelper.readString(key: refreshTokenKey),
              let url = URL(string: "https://github.com/login/oauth/access_token") else {
            logger.warning("No refresh token available")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientID)&grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)

            guard let newAccessToken = tokenResponse.accessToken else {
                logger.error("Refresh response missing access_token")
                return false
            }

            KeychainHelper.saveString(key: accessTokenKey, value: newAccessToken)
            if let newRefreshToken = tokenResponse.refreshToken {
                KeychainHelper.saveString(key: refreshTokenKey, value: newRefreshToken)
            }

            logger.info("Token refreshed successfully")
            await validateToken()
            return true
        } catch {
            logger.error("Refresh token error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Repos

    func fetchRepos() async {
        var allRepos: [GitHubRepo] = []
        var page = 1

        while true {
            guard let data = await apiGet(path: "/user/repos?per_page=100&page=\(page)&sort=updated") else { break }
            guard let pageRepos = try? JSONDecoder().decode([GitHubRepo].self, from: data) else { break }
            if pageRepos.isEmpty { break }
            allRepos.append(contentsOf: pageRepos)
            if pageRepos.count < 100 { break }
            page += 1
        }

        repos = allRepos
        logger.info("Fetched \(allRepos.count) repos")

        // Sync config repos with fetched repos
        if var cfg = config {
            let existingKeys = Set(cfg.repos.map { "\($0.owner)/\($0.name)" })
            for repo in allRepos {
                let key = "\(repo.owner.login)/\(repo.name)"
                if !existingKeys.contains(key) {
                    cfg.repos.append(GitHubRepoConfig(
                        owner: repo.owner.login,
                        name: repo.name,
                        enabled: false
                    ))
                }
            }
            config = cfg
            saveConfig()
        }
    }

    // MARK: - Repo Config Helpers

    func isRepoEnabled(_ repo: GitHubRepo) -> Bool {
        let key = "\(repo.owner.login)/\(repo.name)"
        return config?.repos.first(where: { "\($0.owner)/\($0.name)" == key })?.enabled ?? false
    }

    func toggleRepo(_ repo: GitHubRepo, enabled: Bool) {
        guard var cfg = config else { return }
        let key = "\(repo.owner.login)/\(repo.name)"
        if let idx = cfg.repos.firstIndex(where: { "\($0.owner)/\($0.name)" == key }) {
            cfg.repos[idx].enabled = enabled
        } else {
            cfg.repos.append(GitHubRepoConfig(
                owner: repo.owner.login,
                name: repo.name,
                enabled: enabled
            ))
        }
        config = cfg
        saveConfig()
    }

    func updateRepos(_ repos: [GitHubRepoConfig]) {
        guard var cfg = config else { return }
        cfg.repos = repos
        config = cfg
        saveConfig()
    }

    func updateWebhookSecret(_ secret: String) {
        guard var cfg = config else { return }
        cfg.webhookSecret = secret
        config = cfg
        saveConfig()
    }

    // MARK: - Webhook Management

    func createRepoWebhook(owner: String, name: String, webhookURL: String, secret: String) async -> Int? {
        let payload: [String: Any] = [
            "name": "web",
            "active": true,
            "events": ["check_run", "pull_request"],
            "config": [
                "url": webhookURL,
                "content_type": "json",
                "secret": secret
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        guard let data = await apiPost(path: "/repos/\(owner)/\(name)/hooks", body: body) else { return nil }

        guard let response = try? JSONDecoder().decode(GitHubWebhookResponse.self, from: data) else {
            logger.warning("Failed to decode webhook creation response for \(owner)/\(name)")
            return nil
        }

        // Store webhookId in config
        guard var cfg = config else { return response.id }
        let key = "\(owner)/\(name)"
        if let idx = cfg.repos.firstIndex(where: { "\($0.owner)/\($0.name)" == key }) {
            cfg.repos[idx].webhookId = response.id
            config = cfg
            saveConfig()
        }

        logger.info("Created webhook \(response.id) for \(owner)/\(name)")
        return response.id
    }

    func deleteRepoWebhook(owner: String, name: String, hookId: Int) async -> Bool {
        let success = await apiDelete(path: "/repos/\(owner)/\(name)/hooks/\(hookId)")
        if success {
            guard var cfg = config else { return true }
            let key = "\(owner)/\(name)"
            if let idx = cfg.repos.firstIndex(where: { "\($0.owner)/\($0.name)" == key }) {
                cfg.repos[idx].webhookId = nil
                config = cfg
                saveConfig()
            }
            logger.info("Deleted webhook \(hookId) for \(owner)/\(name)")
        } else {
            logger.warning("Failed to delete webhook \(hookId) for \(owner)/\(name)")
        }
        return success
    }

    func syncWebhooks(webhookURL: String) async {
        guard let cfg = config, let secret = cfg.webhookSecret, !secret.isEmpty else { return }

        for repo in cfg.repos where repo.enabled && repo.webhookId == nil {
            let _ = await createRepoWebhook(
                owner: repo.owner,
                name: repo.name,
                webhookURL: webhookURL,
                secret: secret
            )
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        KeychainHelper.delete(key: accessTokenKey)
        KeychainHelper.delete(key: refreshTokenKey)
        isConnected = false
        username = ""
        repos = []
        config = nil
        try? FileManager.default.removeItem(at: configURL)
        logger.info("Disconnected from GitHub")
    }

    // MARK: - Config Persistence

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(GitHubConfig.self, from: data) else { return }
        config = cfg
        username = cfg.username
    }

    private func saveConfig() {
        guard let cfg = config else { return }
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder().encode(cfg) {
            FileManager.default.createFile(atPath: configURL.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }
}
