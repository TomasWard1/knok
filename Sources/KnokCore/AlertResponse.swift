import Foundation

/// The response sent back from the Knok app to the caller
public struct AlertResponse: Codable, Sendable {
    /// The action taken by the human
    public let action: String

    /// Pre-defined action values
    public static let dismissed = AlertResponse(action: "dismissed")
    public static let timeout = AlertResponse(action: "timeout")
    public static let queueFull = AlertResponse(action: "queue_full")

    public static func buttonClicked(_ id: String) -> AlertResponse {
        AlertResponse(action: id)
    }

    public init(action: String) {
        self.action = action
    }
}
