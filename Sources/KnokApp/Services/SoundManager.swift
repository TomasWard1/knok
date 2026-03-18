import AppKit

@MainActor
final class SoundManager {
    var volume: Float = 0.7

    func play(_ name: String) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }

    func preview(_ name: String) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }
}
