import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Sounds") {
                Toggle("Enable sounds", isOn: $settings.soundEnabled)

                if settings.soundEnabled {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.soundVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Whisper", isOn: $settings.whisperSoundEnabled)
                    Toggle("Nudge", isOn: $settings.nudgeSoundEnabled)
                    Toggle("Knock", isOn: $settings.knockSoundEnabled)
                    Toggle("Break", isOn: $settings.breakSoundEnabled)
                }
            }

            Section("Text-to-Speech") {
                Toggle("Enable TTS", isOn: $settings.ttsEnabled)

                if settings.ttsEnabled {
                    Picker("Voice", selection: $settings.ttsVoice) {
                        Text("System Default").tag("")
                        ForEach(availableVoices, id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }

                    HStack {
                        Text("Rate")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.ttsRate, in: 0...1)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Socket", value: "~/.knok/knok.sock")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
    }

    private var availableVoices: [(name: String, identifier: String)] {
        NSSpeechSynthesizer.availableVoices.compactMap { voice in
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
            guard let name = attrs[.name] as? String else { return nil }
            return (name: name, identifier: voice.rawValue)
        }
    }
}
