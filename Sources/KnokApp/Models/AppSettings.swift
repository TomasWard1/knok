import SwiftUI
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("soundEnabled") var soundEnabled: Bool = true
    @AppStorage("soundVolume") var soundVolume: Double = 0.7
    @AppStorage("whisperSoundEnabled") var whisperSoundEnabled: Bool = true
    @AppStorage("nudgeSoundEnabled") var nudgeSoundEnabled: Bool = true
    @AppStorage("knockSoundEnabled") var knockSoundEnabled: Bool = true
    @AppStorage("breakSoundEnabled") var breakSoundEnabled: Bool = true
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = true
    @AppStorage("ttsVoice") var ttsVoice: String = ""
    @AppStorage("ttsRate") var ttsRate: Double = 0.5
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
            // If registration fails, revert the toggle
            self.launchAtLogin = !launchAtLogin
        }
    }
}
