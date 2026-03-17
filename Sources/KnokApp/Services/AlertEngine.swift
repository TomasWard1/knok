import AppKit
import KnokCore

@MainActor
final class AlertEngine {
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

        // Play sound
        switch payload.level {
        case .whisper:
            soundManager?.playWhisper()
        case .nudge:
            soundManager?.playNudge()
        case .knock, .break:
            soundManager?.playKnock()
        }

        // TTS if requested
        if payload.tts {
            ttsManager?.speak(payload.message ?? payload.title)
        }

        // Show the appropriate view — WindowManager owns the completion
        windowManager?.showAlert(payload: payload) { [weak self] response in
            self?.ttsManager?.stop()
            completion(response)
        }
    }

    func dismissCurrent() {
        ttsManager?.stop()
        windowManager?.dismissAll()
    }
}
