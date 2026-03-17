import AppKit

@MainActor
final class TTSManager {
    private let synthesizer = NSSpeechSynthesizer()

    func setVoice(_ identifier: String) {
        synthesizer.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: identifier))
    }

    func setRate(_ normalizedRate: Double) {
        // Map 0.0-1.0 to reasonable speech rate range (90-300 words per minute)
        let minRate: Float = 90
        let maxRate: Float = 300
        synthesizer.rate = minRate + Float(normalizedRate) * (maxRate - minRate)
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking()
        synthesizer.startSpeaking(text)
    }

    func stop() {
        synthesizer.stopSpeaking()
    }
}
