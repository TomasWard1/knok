import AppKit

@MainActor
final class SoundManager {
    func playWhisper() {
        NSSound(named: "Pop")?.play()
    }

    func playNudge() {
        NSSound(named: "Glass")?.play()
    }

    func playKnock() {
        NSSound(named: "Hero")?.play()
    }
}
