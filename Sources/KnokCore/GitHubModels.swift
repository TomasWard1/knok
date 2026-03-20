import Foundation

// MARK: - Config Models (persisted to ~/.knok/github.json)

/// GitHub integration configuration
public struct GitHubConfig: Codable, Sendable {
    public var username: String
    public var repos: [GitHubRepoConfig]

    public init(username: String, repos: [GitHubRepoConfig] = []) {
        self.username = username
        self.repos = repos
    }
}

/// Per-repo monitoring configuration
public struct GitHubRepoConfig: Codable, Sendable {
    public var owner: String
    public var name: String
    public var enabled: Bool
    public var notifications: NotificationPreferences
    /// PR numbers we've already notified as "ready to merge"
    public var notifiedPRs: Set<Int>

    public init(
        owner: String,
        name: String,
        enabled: Bool = true,
        notifications: NotificationPreferences = NotificationPreferences(),
        notifiedPRs: Set<Int> = []
    ) {
        self.owner = owner
        self.name = name
        self.enabled = enabled
        self.notifications = notifications
        self.notifiedPRs = notifiedPRs
    }

    private enum CodingKeys: String, CodingKey {
        case owner, name, enabled, notifications
        case notifiedPRs = "notified_prs"
    }
}

/// Notification preferences for a monitored repo
public struct NotificationPreferences: Codable, Sendable {
    public var prReadyToMerge: Bool
    public var ciFailure: Bool

    public init(
        prReadyToMerge: Bool = true,
        ciFailure: Bool = true
    ) {
        self.prReadyToMerge = prReadyToMerge
        self.ciFailure = ciFailure
    }

    private enum CodingKeys: String, CodingKey {
        case prReadyToMerge = "pr_ready_to_merge"
        case ciFailure = "ci_failure"
    }
}

// MARK: - API Response Models

/// Response from GET /repos/{owner}/{repo}/actions/runs
public struct GitHubWorkflowRunsResponse: Codable, Sendable {
    public let totalCount: Int
    public let workflowRuns: [GitHubWorkflowRun]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }
}

/// A single workflow run from the GitHub Actions API
public struct GitHubWorkflowRun: Codable, Sendable {
    public let id: Int
    public let name: String
    public let headBranch: String
    public let status: String
    public let conclusion: String?
    public let htmlUrl: String
    public let createdAt: String
    public let updatedAt: String
    public let event: String

    private enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, event
        case headBranch = "head_branch"
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A GitHub repository from the API
public struct GitHubRepo: Codable, Sendable {
    public let id: Int
    public let fullName: String
    public let name: String
    public let owner: GitHubRepoOwner
    public let isPrivate: Bool
    public let htmlUrl: String

    private enum CodingKeys: String, CodingKey {
        case id, name, owner
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlUrl = "html_url"
    }
}

/// Repository owner info
public struct GitHubRepoOwner: Codable, Sendable {
    public let login: String
}

// MARK: - Device Flow OAuth Models

/// Response from POST https://github.com/login/device/code
public struct GitHubDeviceCodeResponse: Codable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

/// A pull request from the GitHub API
public struct GitHubPullRequest: Codable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let htmlUrl: String
    public let state: String
    public let draft: Bool
    public let user: GitHubRepoOwner
    public let head: GitHubPRRef
    public let base: GitHubPRRef
    public let mergeableState: String?
    public let mergeable: Bool?
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, number, title, state, draft, user, head, base, mergeable
        case htmlUrl = "html_url"
        case mergeableState = "mergeable_state"
        case updatedAt = "updated_at"
    }
}

/// PR branch reference
public struct GitHubPRRef: Codable, Sendable {
    public let ref: String
    public let sha: String
}

/// Combined commit status response
public struct GitHubCombinedStatus: Codable, Sendable {
    public let state: String  // "success", "failure", "pending"
    public let totalCount: Int

    private enum CodingKeys: String, CodingKey {
        case state
        case totalCount = "total_count"
    }
}

/// Check runs response (GitHub Actions)
public struct GitHubCheckRunsResponse: Codable, Sendable {
    public let totalCount: Int
    public let checkRuns: [GitHubCheckRun]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case checkRuns = "check_runs"
    }
}

/// A single check run
public struct GitHubCheckRun: Codable, Sendable {
    public let id: Int
    public let status: String       // "completed", "in_progress", "queued"
    public let conclusion: String?  // "success", "failure", etc.
}

/// Response from POST https://github.com/login/oauth/access_token
public struct GitHubTokenResponse: Codable, Sendable {
    public let accessToken: String?
    public let tokenType: String?
    public let scope: String?
    public let refreshToken: String?
    public let refreshTokenExpiresIn: Int?
    public let error: String?
    public let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case error
        case errorDescription = "error_description"
    }
}
