// PLACEHOLDER — to be implemented by agent
import AppKit
import KnokCore

@MainActor
final class AlertEngine {
    private var windowManager: WindowManager?
    private var ttsManager: TTSManager?
    private var soundManager: SoundManager?
    private var currentCompletion: ((AlertResponse) -> Void)?

    nonisolated init() {}

    private func ensureInitialized() {
        if windowManager == nil { windowManager = WindowManager() }
        if ttsManager == nil { ttsManager = TTSManager() }
        if soundManager == nil { soundManager = SoundManager() }
    }

    func showAlert(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        ensureInitialized()

        // Dismiss any current alert
        dismissCurrent()
        currentCompletion = completion

        // Play sound for knock and break levels
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
            let text = payload.message ?? payload.title
            ttsManager?.speak(text)
        }

        // Show the appropriate view
        windowManager?.showAlert(payload: payload) { [weak self] response in
            self?.ttsManager?.stop()
            self?.currentCompletion?(response)
            self?.currentCompletion = nil
        }
    }

    func dismissCurrent() {
        ttsManager?.stop()
        windowManager?.dismissAll()
        if let completion = currentCompletion {
            completion(.dismissed)
            currentCompletion = nil
        }
    }
}
