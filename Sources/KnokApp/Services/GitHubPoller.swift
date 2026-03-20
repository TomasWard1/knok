import Foundation
import KnokCore

@MainActor
final class GitHubPoller {
    private let service: GitHubService
    private let alertEngine: AlertEngine
    private var timer: Timer?

    enum PRStatus {
        case ready
        case failing
        case pending
    }

    init(service: GitHubService, alertEngine: AlertEngine) {
        self.service = service
        self.alertEngine = alertEngine
    }

    func start() {
        print("[GitHubPoller] Starting poller (60s interval)")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.poll()
            }
        }
        // Also poll immediately
        Task { await poll() }
    }

    func stop() {
        print("[GitHubPoller] Stopping poller")
        timer?.invalidate()
        timer = nil
    }

    private func poll() async {
        guard let config = service.config else {
            print("[GitHubPoller] No config, skipping poll")
            return
        }

        let enabledRepos = config.repos.filter { $0.enabled }
        print("[GitHubPoller] Polling \(enabledRepos.count) enabled repos")

        for repoConfig in enabledRepos {
            let key = "\(repoConfig.owner)/\(repoConfig.name)"
            print("[GitHubPoller] Checking repo: \(key)")

            guard let data = await service.apiGet(path: "/repos/\(key)/pulls?state=open&sort=updated&direction=desc&per_page=10") else {
                print("[GitHubPoller] Failed to fetch PRs for \(key)")
                continue
            }

            guard let prs = try? JSONDecoder().decode([GitHubPullRequest].self, from: data) else {
                print("[GitHubPoller] Failed to decode PRs for \(key)")
                continue
            }

            let nonDraftPRs = prs.filter { !$0.draft }
            print("[GitHubPoller] Found \(nonDraftPRs.count) non-draft PRs for \(key)")

            for pr in nonDraftPRs {
                let status = await checkPRStatus(repoKey: key, sha: pr.head.sha)
                print("[GitHubPoller] PR #\(pr.number) status: \(status)")

                let alreadyNotified = repoConfig.notifiedPRs.contains(pr.number)

                switch status {
                case .ready:
                    if !alreadyNotified && repoConfig.notifications.prReadyToMerge {
                        print("[GitHubPoller] Showing ready-to-merge alert for PR #\(pr.number)")
                        showReadyAlert(repo: key, pr: pr)
                        markNotified(owner: repoConfig.owner, name: repoConfig.name, prNumber: pr.number)
                    }
                case .failing:
                    if !alreadyNotified && repoConfig.notifications.ciFailure {
                        print("[GitHubPoller] Showing CI failure alert for PR #\(pr.number)")
                        showFailureAlert(repo: key, pr: pr)
                        markNotified(owner: repoConfig.owner, name: repoConfig.name, prNumber: pr.number)
                    }
                case .pending:
                    break
                }
            }

            // Clean up notified PRs that are no longer open
            cleanUpClosedPRs(owner: repoConfig.owner, name: repoConfig.name, openPRNumbers: Set(prs.map { $0.number }))
        }
    }

    private func checkPRStatus(repoKey: String, sha: String) async -> PRStatus {
        // Try check-runs first (GitHub Actions)
        if let data = await service.apiGet(path: "/repos/\(repoKey)/commits/\(sha)/check-runs?per_page=100"),
           let checkRuns = try? JSONDecoder().decode(GitHubCheckRunsResponse.self, from: data),
           checkRuns.totalCount > 0 {

            let runs = checkRuns.checkRuns
            let allCompleted = runs.allSatisfy { $0.status == "completed" }

            if !allCompleted { return .pending }

            let anyFailure = runs.contains { $0.conclusion == "failure" || $0.conclusion == "timed_out" || $0.conclusion == "cancelled" }
            if anyFailure { return .failing }

            return .ready
        }

        // Fall back to legacy status API
        if let data = await service.apiGet(path: "/repos/\(repoKey)/commits/\(sha)/status"),
           let combined = try? JSONDecoder().decode(GitHubCombinedStatus.self, from: data) {

            if combined.totalCount == 0 { return .ready }

            switch combined.state {
            case "success": return .ready
            case "failure", "error": return .failing
            default: return .pending
            }
        }

        print("[GitHubPoller] Failed to get CI status for \(repoKey) @ \(sha)")
        return .pending
    }

    private func showReadyAlert(repo: String, pr: GitHubPullRequest) {
        let payload = AlertPayload(
            level: .nudge,
            title: "PR Ready to Merge",
            message: "\(repo) #\(pr.number): \(pr.title)",
            actions: [
                AlertAction(label: "Open PR", id: "open", url: pr.htmlUrl)
            ],
            icon: "checkmark.circle.fill",
            color: "#34D399"
        )
        alertEngine.showAlert(payload: payload) { _ in }
    }

    private func showFailureAlert(repo: String, pr: GitHubPullRequest) {
        let payload = AlertPayload(
            level: .knock,
            title: "CI Failed",
            message: "\(repo) #\(pr.number): \(pr.title)",
            actions: [
                AlertAction(label: "Open PR", id: "open", url: pr.htmlUrl)
            ],
            icon: "xmark.circle.fill",
            color: "#EF4444"
        )
        alertEngine.showAlert(payload: payload) { _ in }
    }

    private func markNotified(owner: String, name: String, prNumber: Int) {
        guard var cfg = service.config else { return }
        let key = "\(owner)/\(name)"
        if let idx = cfg.repos.firstIndex(where: { "\($0.owner)/\($0.name)" == key }) {
            cfg.repos[idx].notifiedPRs.insert(prNumber)
            service.updateRepos(cfg.repos)
        }
    }

    private func cleanUpClosedPRs(owner: String, name: String, openPRNumbers: Set<Int>) {
        guard var cfg = service.config else { return }
        let key = "\(owner)/\(name)"
        if let idx = cfg.repos.firstIndex(where: { "\($0.owner)/\($0.name)" == key }) {
            let closedPRs = cfg.repos[idx].notifiedPRs.subtracting(openPRNumbers)
            if !closedPRs.isEmpty {
                cfg.repos[idx].notifiedPRs.subtract(closedPRs)
                service.updateRepos(cfg.repos)
            }
        }
    }
}
