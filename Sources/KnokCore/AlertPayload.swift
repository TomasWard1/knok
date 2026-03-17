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

    public init(
        level: AlertLevel,
        title: String,
        message: String? = nil,
        tts: Bool = false,
        actions: [AlertAction] = [],
        ttl: Int = 0
    ) {
        self.level = level
        self.title = title
        self.message = message
        self.tts = tts
        self.actions = actions
        self.ttl = ttl
    }
}
