import Foundation
import KnokCore

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
            Task { await fetchRepos() }
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
                startPolling()
            } catch {
                print("[GitHubService] Device flow error: \(error)")
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
                    // expired_token or other error
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

            await fetchRepos()
        } catch {
            print("[GitHubService] Poll error: \(error)")
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
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    return await apiGet(path: path)
                } else {
                    disconnect()
                    return nil
                }
            }
            return data
        } catch {
            print("[GitHubService] API error for \(path): \(error)")
            return nil
        }
    }

    private func refreshAccessToken() async -> Bool {
        guard let refreshToken = KeychainHelper.readString(key: refreshTokenKey),
              let url = URL(string: "https://github.com/login/oauth/access_token") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientID)&grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)

            guard let newAccessToken = tokenResponse.accessToken else { return false }
            KeychainHelper.saveString(key: accessTokenKey, value: newAccessToken)
            if let newRefreshToken = tokenResponse.refreshToken {
                KeychainHelper.saveString(key: refreshTokenKey, value: newRefreshToken)
            }
            return true
        } catch {
            print("[GitHubService] Refresh token error: \(error)")
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

    // MARK: - Disconnect

    func disconnect() {
        KeychainHelper.delete(key: accessTokenKey)
        KeychainHelper.delete(key: refreshTokenKey)
        isConnected = false
        username = ""
        repos = []
        config = nil
        try? FileManager.default.removeItem(at: configURL)
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: configURL)
        }
    }
}
