import Foundation

/// The alert payload sent from CLI/MCP to the Knok app
public struct AlertPayload: Codable, Sendable {
    /// Urgency level
    public let level: AlertLevel
    /// Alert title
    public let title: String
    /// Alert body text (optional)
    public let message: String?
    /// Whether to speak the message via TTS
    public let tts: Bool
    /// Action buttons for the human to respond with
    public let actions: [AlertAction]
    /// Auto-dismiss after N seconds (0 = never)
    public let ttl: Int
    /// SF Symbol name for the alert icon (auto-detected from title if nil)
    public let icon: String?
    /// Hex color for accent (e.g. "#FF6B6B"). Auto-detected from title if nil
    public let color: String?

    public init(
        level: AlertLevel,
        title: String,
        message: String? = nil,
        tts: Bool = false,
        actions: [AlertAction] = [],
        ttl: Int = 0,
        icon: String? = nil,
        color: String? = nil
    ) {
        self.level = level
        self.title = title
        self.message = message
        self.tts = tts
        self.actions = actions
        self.ttl = ttl
        self.icon = icon
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(AlertLevel.self, forKey: .level)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        tts = try container.decodeIfPresent(Bool.self, forKey: .tts) ?? false
        actions = try container.decodeIfPresent([AlertAction].self, forKey: .actions) ?? []
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl) ?? 0
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
    }

    private enum CodingKeys: String, CodingKey {
        case level, title, message, tts, actions, ttl, icon, color
    }
}
