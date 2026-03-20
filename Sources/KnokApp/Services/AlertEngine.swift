import AppKit
import KnokCore

@MainActor
final class AlertEngine {
    lazy var history = AlertHistory()
    var settings: AppSettings?

    private var windowManager: WindowManager?
    private var ttsManager: TTSManager?
    private var soundManager: SoundManager?
    private var queue: AlertQueue?

    nonisolated init() {}

    private func ensureInitialized() {
        if windowManager == nil { windowManager = WindowManager() }
        if ttsManager == nil { ttsManager = TTSManager() }
        if soundManager == nil { soundManager = SoundManager() }
        if queue == nil {
            let q = AlertQueue()
            q.onShow = { [weak self] payload, level, completion in
                self?.displayAlert(payload: payload, level: level, completion: completion)
            }
            q.onSuspend = { [weak self] level in
                self?.windowManager?.suspendLevel(level)
            }
            q.onResume = { [weak self] level in
                self?.windowManager?.resumeLevel(level)
            }
            q.onQueueDepthChanged = { [weak self] level, depth in
                self?.windowManager?.updateStackHints(level: level, depth: depth)
            }
            queue = q
        }
    }

    func showAlert(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        ensureInitialized()

        let itemId = history.record(payload: payload)

        // Play sound on arrival (even if queued)
        playSound(for: payload)

        // Try to enqueue — reject if queue is full
        let enqueued = queue!.enqueue(payload: payload) { [weak self] response in
            self?.history.recordResponse(response, for: itemId)
            completion(response)
        }

        if !enqueued {
            history.recordResponse(.queueFull, for: itemId)
            completion(.queueFull)
        }
    }

    /// Called by AlertQueue.onShow — displays the alert UI and TTS
    private func displayAlert(payload: AlertPayload, level: AlertLevel, completion: @escaping (AlertResponse) -> Void) {
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

        // Show the alert — pass stack depth for visual hints
        let stackDepth = queue?.pendingCount(for: level) ?? 0
        windowManager?.showAlert(payload: payload, stackDepth: stackDepth) { [weak self] response in
            self?.ttsManager?.stop()
            completion(response)
        }
    }

    private func playSound(for payload: AlertPayload) {
        if let volume = settings?.soundVolume {
            soundManager?.volume = Float(volume)
        }
        guard settings?.soundEnabled != false else { return }
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

    func dismissCurrent() {
        ttsManager?.stop()
        // Dismiss highest-priority active level
        if let queue = queue {
            for level in [AlertLevel.break, .knock, .nudge, .whisper] {
                if queue.active[level] != nil {
                    queue.complete(level: level, response: .dismissed)
                    return
                }
            }
        }
        windowManager?.dismissAll()
    }
}
