import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            soundsTab
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            speechTab
                .tabItem { Label("Speech", systemImage: "waveform") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 380)
        .padding(.top, 8)
    }

    // MARK: - Sounds Tab

    private var soundsTab: some View {
        Form {
            Toggle("Enable sounds", isOn: $settings.soundEnabled)

            if settings.soundEnabled {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.soundVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                soundRow("Whisper", enabled: $settings.whisperSoundEnabled, sound: $settings.whisperSound)
                soundRow("Nudge", enabled: $settings.nudgeSoundEnabled, sound: $settings.nudgeSound)
                soundRow("Knock", enabled: $settings.knockSoundEnabled, sound: $settings.knockSound)
                soundRow("Break", enabled: $settings.breakSoundEnabled, sound: $settings.breakSound)
            }
        }
        .formStyle(.grouped)
    }

    private func soundRow(_ label: String, enabled: Binding<Bool>, sound: Binding<String>) -> some View {
        HStack {
            Toggle(label, isOn: enabled)
            Spacer()
            if enabled.wrappedValue {
                Picker("", selection: sound) {
                    ForEach(AppSettings.systemSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(width: 120)

                Button {
                    if let s = NSSound(named: sound.wrappedValue) {
                        s.volume = Float(settings.soundVolume)
                        s.play()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Preview sound")
            }
        }
    }

    // MARK: - Speech Tab

    private var speechTab: some View {
        Form {
            Toggle("Enable text-to-speech", isOn: $settings.ttsEnabled)

            if settings.ttsEnabled {
                Picker("Voice", selection: $settings.ttsVoice) {
                    Text("System Default").tag("")
                    ForEach(availableVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }

                HStack {
                    Text("Speed")
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.ttsRate, in: 0...1)
                    Text(rateLabel)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                Button("Preview") {
                    let synth = NSSpeechSynthesizer()
                    if !settings.ttsVoice.isEmpty {
                        synth.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: settings.ttsVoice))
                    }
                    let minRate: Float = 90
                    let maxRate: Float = 300
                    synth.rate = minRate + Float(settings.ttsRate) * (maxRate - minRate)
                    synth.startSpeaking("Hey, you have a meeting in 5 minutes.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var rateLabel: String {
        if settings.ttsRate < 0.3 { return "Slow" }
        if settings.ttsRate < 0.7 { return "Normal" }
        return "Fast"
    }

    private var availableVoices: [(name: String, identifier: String)] {
        NSSpeechSynthesizer.availableVoices.compactMap { voice in
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
            guard let name = attrs[.name] as? String else { return nil }
            return (name: name, identifier: voice.rawValue)
        }
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Picker("Font size", selection: $settings.fontScale) {
                Text("Small").tag(0.85)
                Text("Medium").tag(1.0)
                Text("Large").tag(1.15)
            }
            .pickerStyle(.segmented)

            Text("Preview: The quick brown fox")
                .font(.system(size: 16 * settings.fontScale, design: .rounded))
                .padding(.top, 4)
        }
        .formStyle(.grouped)
    }

    // MARK: - Behavior Tab

    private var behaviorTab: some View {
        Form {
            Toggle("Show alerts in all Spaces", isOn: $settings.showInAllSpaces)
                .help("When enabled, alerts follow you across macOS Spaces")

            Section("Auto-dismiss (seconds, 0 = manual)") {
                HStack {
                    Text("Whisper")
                    Spacer()
                    TextField("", value: $settings.whisperAutoDismiss, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("s")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Nudge")
                    Spacer()
                    TextField("", value: $settings.nudgeAutoDismiss, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("s")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        Form {
            LabeledContent("Version", value: "0.1.0")
            LabeledContent("Socket", value: "~/.knok/knok.sock")
            LabeledContent("GitHub", value: "github.com/TomasWard1/knok")
        }
        .formStyle(.grouped)
    }
}
