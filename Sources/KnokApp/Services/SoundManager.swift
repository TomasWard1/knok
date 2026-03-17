import AppKit

@MainActor
final class SoundManager {
    var volume: Float = 0.7

    private func play(_ name: String) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }

    func playWhisper() {
        play("Tink")
    }

    func playNudge() {
        play("Glass")
    }

    func playKnock() {
        play("Purr")
    }

    func playBreak() {
        play("Sosumi")
    }
}
