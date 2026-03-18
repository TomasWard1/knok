import AppKit
import KnokCore

@MainActor
final class AlertEngine {
    lazy var history = AlertHistory()
    var settings: AppSettings?

    private var windowManager: WindowManager?
    private var ttsManager: TTSManager?
    private var soundManager: SoundManager?

    nonisolated init() {}

    private func ensureInitialized() {
        if windowManager == nil { windowManager = WindowManager() }
        if ttsManager == nil { ttsManager = TTSManager() }
        if soundManager == nil { soundManager = SoundManager() }
    }

    func showAlert(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        ensureInitialized()

        let itemId = history.record(payload: payload)

        // Apply volume from settings
        if let volume = settings?.soundVolume {
            soundManager?.volume = Float(volume)
        }

        // Play sound if enabled
        if settings?.soundEnabled != false {
            switch payload.level {
            case .whisper:
                if settings?.whisperSoundEnabled != false {
                    soundManager?.play(settings?.whisperSound ?? "Tink")
                }
            case .nudge:
                if settings?.nudgeSoundEnabled != false {
                    soundManager?.play(settings?.nudgeSound ?? "Glass")
                }
            case .knock:
                if settings?.knockSoundEnabled != false {
                    soundManager?.play(settings?.knockSound ?? "Purr")
                }
            case .break:
                if settings?.breakSoundEnabled != false {
                    soundManager?.play(settings?.breakSound ?? "Sosumi")
                }
            }
        }

        // TTS if requested and enabled
        if payload.tts && settings?.ttsEnabled != false {
            if let voice = settings?.ttsVoice, !voice.isEmpty {
                ttsManager?.setVoice(voice)
            }
            if let rate = settings?.ttsRate {
                ttsManager?.setRate(rate)
            }
            ttsManager?.speak(payload.message ?? payload.title)
        }

        // Pass settings to window manager
        windowManager?.settings = settings

        // Show the appropriate view -- WindowManager owns the completion
        windowManager?.showAlert(payload: payload) { [weak self] response in
            self?.ttsManager?.stop()
            self?.history.recordResponse(response, for: itemId)
            completion(response)
        }
    }

    func dismissCurrent() {
        ttsManager?.stop()
        windowManager?.dismissAll()
    }
}
