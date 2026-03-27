import Foundation
import KnokCore
import CryptoKit
import os

private let logger = Logger(subsystem: "app.getknok.Knok", category: "GitHubWebhookHandler")

/// Lightweight PR reference used internally during check_run processing
private struct PRRef {
    let number: Int
    let sha: String
}

@MainActor
final class GitHubWebhookHandler: ObservableObject {
    private let alertEngine: AlertEngine
    private let gitHubService: GitHubService
    @Published var lastEventDate: Date?

    init(alertEngine: AlertEngine, gitHubService: GitHubService) {
        self.alertEngine = alertEngine
        self.gitHubService = gitHubService
    }

    // MARK: - Public

    func handleRequest(headers: [String: String], body: Data) -> Bool {
        guard let secret = gitHubService.config?.webhookSecret, !secret.isEmpty else {
            logger.warning("No webhook secret configured, rejecting request")
            return false
        }

        guard let signature = headers["x-hub-signature-256"] else {
            logger.warning("Missing x-hub-signature-256 header")
            return false
        }

        guard verifySignature(payload: body, signature: signature, secret: secret) else {
            logger.warning("Invalid webhook signature")
            return false
        }

        let eventType = headers["x-github-event"] ?? "unknown"
        lastEventDate = Date()
        logger.info("Received webhook event: \(eventType)")

        Task { @MainActor in
            await processEvent(type: eventType, body: body)
        }

        return true
    }

    // MARK: - Signature Verification

    private func verifySignature(payload: Data, signature: String, secret: String) -> Bool {
        guard signature.hasPrefix("sha256=") else { return false }
        let hexSignature = String(signature.dropFirst(7))
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        let expectedHex = mac.map { String(format: "%02x", $0) }.joined()
        return hexSignature == expectedHex
    }

    // MARK: - Event Processing

    private func processEvent(type: String, body: Data) async {
        switch type {
        case "check_run":
            await processCheckRun(body: body)
        case "pull_request":
            processPullRequest(body: body)
        case "ping":
            logger.info("Received ping event")
        default:
            logger.debug("Ignoring unhandled event type: \(type)")
        }
    }

    private func processCheckRun(body: Data) async {
        guard let event = try? JSONDecoder().decode(GitHubWebhookCheckRunEvent.self, from: body) else {
            logger.warning("Failed to decode check_run event")
            return
        }

        guard event.action == "completed" else { return }

        let repoFullName = event.repository.fullName
        guard let config = gitHubService.config,
              let repoConfig = config.repos.first(where: { "\($0.owner)/\($0.name)" == repoFullName && $0.enabled }) else {
            logger.debug("Ignoring check_run for untracked repo: \(repoFullName)")
            return
        }

        let conclusion = event.checkRun.conclusion ?? ""
        let headSha = event.checkRun.headSha

        // Resolve associated PRs — webhook payload may have them, but GitHub sometimes sends an empty array
        var prRefs: [PRRef] = event.checkRun.pullRequests.map { PRRef(number: $0.number, sha: $0.head.sha) }
        if prRefs.isEmpty {
            logger.info("check_run payload has empty pull_requests for \(repoFullName), fetching from API")
            prRefs = await fetchPRsForCommit(repo: repoFullName, sha: headSha)
        }

        if prRefs.isEmpty {
            logger.debug("No associated PRs for check_run on \(repoFullName) sha \(headSha)")
            return
        }

        if ["failure", "timed_out", "cancelled"].contains(conclusion) && repoConfig.notifications.ciFailure {
            for pr in prRefs {
                showCIFailureAlert(repo: repoFullName, prNumber: pr.number)
            }
        } else if conclusion == "success" {
            guard repoConfig.notifications.prReadyToMerge else { return }

            // Small delay to let GitHub's API reflect the just-completed check run
            try? await Task.sleep(for: .seconds(3))

            for pr in prRefs {
                await checkAllPassedAndNotify(repo: repoFullName, sha: pr.sha, prNumber: pr.number)
            }
        }
    }

    /// Fetch open PRs whose head SHA matches the given commit
    private func fetchPRsForCommit(repo: String, sha: String) async -> [PRRef] {
        guard let data = await gitHubService.apiGet(path: "/repos/\(repo)/commits/\(sha)/pulls") else {
            logger.warning("Failed to fetch PRs for commit \(sha) on \(repo)")
            return []
        }
        guard let prs = try? JSONDecoder().decode([GitHubCommitPR].self, from: data) else {
            logger.warning("Failed to decode PRs for commit \(sha) on \(repo)")
            return []
        }
        return prs.map { PRRef(number: $0.number, sha: sha) }
    }

    /// Verify all check runs passed for a commit and fire the alert
    private func checkAllPassedAndNotify(repo: String, sha: String, prNumber: Int) async {
        guard let data = await gitHubService.apiGet(path: "/repos/\(repo)/commits/\(sha)/check-runs") else {
            logger.warning("API call failed: /repos/\(repo)/commits/\(sha)/check-runs")
            return
        }
        guard let checkRuns = try? JSONDecoder().decode(GitHubCheckRunsResponse.self, from: data) else {
            logger.warning("Failed to decode check-runs response for \(repo) sha \(sha)")
            return
        }

        let total = checkRuns.checkRuns.count
        let passed = checkRuns.checkRuns.filter { $0.status == "completed" && $0.conclusion == "success" }.count
        let pending = checkRuns.checkRuns.filter { $0.status != "completed" }.count

        if pending > 0 {
            logger.info("PR #\(prNumber) on \(repo): \(passed)/\(total) passed, \(pending) still pending — skipping")
            return
        }

        let allPassed = checkRuns.checkRuns.allSatisfy { $0.status == "completed" && $0.conclusion == "success" }
        if allPassed {
            logger.info("All \(total) checks passed for PR #\(prNumber) on \(repo) — sending ready-to-merge alert")
            showReadyToMergeAlert(repo: repo, prNumber: prNumber)
        } else {
            let failed = checkRuns.checkRuns.filter { $0.status == "completed" && $0.conclusion != "success" }
            logger.info("PR #\(prNumber) on \(repo): \(passed)/\(total) passed, \(failed.count) not successful — skipping")
        }
    }

    private func processPullRequest(body: Data) {
        guard let event = try? JSONDecoder().decode(GitHubWebhookPREvent.self, from: body) else {
            logger.warning("Failed to decode pull_request event")
            return
        }

        let repoFullName = event.repository.fullName
        guard let config = gitHubService.config,
              let repoConfig = config.repos.first(where: { "\($0.owner)/\($0.name)" == repoFullName && $0.enabled }) else {
            logger.debug("Ignoring pull_request for untracked repo: \(repoFullName)")
            return
        }

        switch event.action {
        case "opened":
            if !event.pullRequest.draft && repoConfig.notifications.prOpened {
                showPROpenedAlert(repo: repoFullName, pr: event.pullRequest)
            }
        case "closed":
            if event.pullRequest.merged == true && repoConfig.notifications.prMerged {
                showPRMergedAlert(repo: repoFullName, pr: event.pullRequest)
            }
        default:
            break
        }
    }

    // MARK: - Alerts

    private func showCIFailureAlert(repo: String, prNumber: Int) {
        let payload = AlertPayload(
            level: .knock,
            title: "CI Failed",
            message: "\(repo) #\(prNumber)",
            actions: [AlertAction(label: "Open PR", id: "open", url: "https://github.com/\(repo)/pull/\(prNumber)")],
            icon: "xmark.circle.fill",
            color: "#EF4444"
        )
        alertEngine.showAlert(payload: payload) { _ in }
    }

    private func showReadyToMergeAlert(repo: String, prNumber: Int) {
        let payload = AlertPayload(
            level: .nudge,
            title: "PR Ready to Merge",
            message: "\(repo) #\(prNumber)",
            actions: [AlertAction(label: "Open PR", id: "open", url: "https://github.com/\(repo)/pull/\(prNumber)")],
            icon: "checkmark.circle.fill",
            color: "#34D399"
        )
        alertEngine.showAlert(payload: payload) { _ in }
    }

    private func showPROpenedAlert(repo: String, pr: GitHubWebhookPREvent.WebhookPullRequest) {
        let payload = AlertPayload(
            level: .nudge,
            title: "New PR",
            message: "\(repo) #\(pr.number): \(pr.title)",
            actions: [AlertAction(label: "Open PR", id: "open", url: pr.htmlUrl)],
            icon: "arrow.triangle.pull",
            color: "#8B5CF6"
        )
        alertEngine.showAlert(payload: payload) { _ in }
    }

    private func showPRMergedAlert(repo: String, pr: GitHubWebhookPREvent.WebhookPullRequest) {
        let payload = AlertPayload(
            level: .whisper,
            title: "PR Merged",
            message: "\(repo) #\(pr.number): \(pr.title)",
            actions: [AlertAction(label: "Open PR", id: "open", url: pr.htmlUrl)],
            icon: "arrow.triangle.merge",
            color: "#8B5CF6"
        )
        alertEngine.showAlert(payload: payload) { _ in }
    }
}
