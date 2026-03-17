import Foundation

/// Alert urgency levels, from lowest to highest
public enum AlertLevel: String, Codable, Sendable, CaseIterable {
    /// Menu bar icon flash + optional sound. Low priority FYI.
    case whisper
    /// Floating notification banner that stays until dismissed.
    case nudge
    /// Semi-transparent overlay + sound + optional TTS.
    case knock
    /// Full-screen takeover, blur background, TTS, must dismiss.
    case `break`
}
