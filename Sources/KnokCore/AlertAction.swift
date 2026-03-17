import Foundation

/// A button action that the human can click to respond
public struct AlertAction: Codable, Sendable, Hashable {
    /// Display label for the button
    public let label: String
    /// Identifier returned when this button is clicked
    public let id: String
    /// Optional URL to open when clicked (instead of just returning the id)
    public let url: String?
    /// SF Symbol name for button icon (optional)
    public let icon: String?

    public init(label: String, id: String, url: String? = nil, icon: String? = nil) {
        self.label = label
        self.id = id
        self.url = url
        self.icon = icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
    }

    private enum CodingKeys: String, CodingKey {
        case label, id, url, icon
    }
}
