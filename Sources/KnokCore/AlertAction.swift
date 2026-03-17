import Foundation

/// A button action that the human can click to respond
public struct AlertAction: Codable, Sendable, Hashable {
    /// Display label for the button
    public let label: String
    /// Identifier returned when this button is clicked
    public let id: String

    public init(label: String, id: String) {
        self.label = label
        self.id = id
    }
}
