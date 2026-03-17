import SwiftUI
import KnokCore

// MARK: - Color Palette

enum KnokColors {
    static let success = Color(red: 0.35, green: 0.84, blue: 0.56)   // Mint green
    static let error = Color(red: 1.0, green: 0.42, blue: 0.42)      // Soft coral
    static let info = Color(red: 0.40, green: 0.65, blue: 1.0)       // Sky blue
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.30)    // Warm amber
    static let accent = Color(red: 0.65, green: 0.50, blue: 1.0)     // Soft violet

    /// Parse hex string like "#FF6B6B" or "FF6B6B" to Color
    static func fromHex(_ hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Payload Helpers

extension AlertPayload {
    /// Resolved accent color: custom hex > auto-detect from title
    func resolvedAccentColor() -> Color {
        if let hex = color, let custom = KnokColors.fromHex(hex) {
            return custom
        }
        if title.localizedCaseInsensitiveContains("error") ||
           title.localizedCaseInsensitiveContains("fail") {
            return KnokColors.error
        }
        if title.localizedCaseInsensitiveContains("build") ||
           title.localizedCaseInsensitiveContains("deploy") ||
           title.localizedCaseInsensitiveContains("pass") {
            return KnokColors.success
        }
        if title.localizedCaseInsensitiveContains("pr") ||
           title.localizedCaseInsensitiveContains("review") {
            return KnokColors.accent
        }
        return KnokColors.info
    }

    /// Resolved icon: custom SF Symbol > auto-detect from title
    func resolvedIcon() -> String {
        if let custom = icon { return custom }
        if title.localizedCaseInsensitiveContains("build") ||
           title.localizedCaseInsensitiveContains("deploy") {
            return "bolt.fill"
        }
        if title.localizedCaseInsensitiveContains("test") ||
           title.localizedCaseInsensitiveContains("pass") {
            return "checkmark.circle.fill"
        }
        if title.localizedCaseInsensitiveContains("error") ||
           title.localizedCaseInsensitiveContains("fail") {
            return "xmark.circle.fill"
        }
        if title.localizedCaseInsensitiveContains("pr") ||
           title.localizedCaseInsensitiveContains("review") {
            return "arrow.triangle.pull"
        }
        switch level {
        case .whisper: return "bell.fill"
        case .nudge: return "hand.tap.fill"
        case .knock: return "exclamationmark.triangle.fill"
        case .break: return "exclamationmark.octagon.fill"
        }
    }
}
