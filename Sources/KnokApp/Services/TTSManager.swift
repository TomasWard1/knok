import AppKit

@MainActor
final class TTSManager {
    private let synthesizer = NSSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking()
        synthesizer.startSpeaking(text)
    }

    func stop() {
        synthesizer.stopSpeaking()
    }
}
