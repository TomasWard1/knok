import SwiftUI
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    // MARK: - Sounds
    @AppStorage("soundEnabled") var soundEnabled: Bool = true
    @AppStorage("soundVolume") var soundVolume: Double = 0.7
    @AppStorage("whisperSoundEnabled") var whisperSoundEnabled: Bool = true
    @AppStorage("nudgeSoundEnabled") var nudgeSoundEnabled: Bool = true
    @AppStorage("knockSoundEnabled") var knockSoundEnabled: Bool = true
    @AppStorage("breakSoundEnabled") var breakSoundEnabled: Bool = true
    @AppStorage("whisperSound") var whisperSound: String = "Tink"
    @AppStorage("nudgeSound") var nudgeSound: String = "Glass"
    @AppStorage("knockSound") var knockSound: String = "Purr"
    @AppStorage("breakSound") var breakSound: String = "Sosumi"

    // MARK: - TTS
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = true
    @AppStorage("ttsVoice") var ttsVoice: String = ""
    @AppStorage("ttsRate") var ttsRate: Double = 0.35

    // MARK: - Appearance
    @AppStorage("fontScale") var fontScale: Double = 1.0  // 0.85 small, 1.0 medium, 1.15 large

    // MARK: - Behavior
    @AppStorage("showInAllSpaces") var showInAllSpaces: Bool = true
    @AppStorage("whisperAutoDissmiss") var whisperAutoDismiss: Int = 5
    @AppStorage("nudgeAutoDismiss") var nudgeAutoDismiss: Int = 0

    // MARK: - General
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { updateLaunchAtLogin() }
    }

    nonisolated init() {}

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.launchAtLogin = !launchAtLogin
        }
    }

    static let systemSounds: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
        "Submarine", "Tink"
    ]
}
