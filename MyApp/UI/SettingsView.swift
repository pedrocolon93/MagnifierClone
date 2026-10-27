import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ask input") {
                    Picker("Input mode", selection: $settings.inputMode) {
                        Text("Voice").tag(InputMode.voice)
                        Text("Text").tag(InputMode.text)
                        Text("Ask each time").tag(InputMode.askEachTime)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Answer style", selection: $settings.answerStyle) {
                        Text("Standard").tag(AnswerStyle.standard)
                        Text("Accessibility").tag(AnswerStyle.accessibility)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Answers")
                } footer: {
                    Text(settings.answerStyle == .standard
                        ? "Answers the question as asked."
                        : "Also describes the details that matter, where things are, and what you could do next.")
                }
                Section("While waiting") {
                    NavigationLink {
                        SoundPicker(selection: $settings.waitingSound)
                    } label: {
                        LabeledContent("Sound", value: soundName)
                    }
                    Toggle("Vibrate", isOn: $settings.vibrates)
                    secondsSlider(
                        "Start after", value: $settings.waitDelay, in: AppSettings.waitDelayRange,
                        zeroText: "Right away", accessibilityLabel: "Delay before the first sound"
                    )
                    secondsSlider(
                        "Repeat every", value: $settings.waitInterval, in: AppSettings.waitIntervalRange,
                        zeroText: nil, accessibilityLabel: "Waiting sound interval"
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var soundName: String {
        switch settings.waitingSound {
        case AppSettings.builtInSound: "Ding"
        case AppSettings.noSound: "None"
        default: SystemSounds.all().first { $0.url.path == settings.waitingSound }?.name
            ?? URL(filePath: settings.waitingSound).deletingPathExtension().lastPathComponent
        }
    }

    private func secondsSlider(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
        zeroText: String?, accessibilityLabel: String
    ) -> some View {
        let text = value.wrappedValue == 0 && zeroText != nil
            ? zeroText!
            : "\(value.wrappedValue.formatted(.number.precision(.fractionLength(1)))) s"
        return VStack(alignment: .leading) {
            LabeledContent(title, value: text)
            Slider(value: value, in: range, step: 0.5)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(text)
        }
    }
}

/// Built-in ding, silence, or any system sound. Tapping a sound selects it and plays it once.
private struct SoundPicker: View {
    @Binding var selection: String
    @State private var sounds: [SoundFile] = []
    @State private var query = ""

    var body: some View {
        List {
            Section {
                row("Ding", value: AppSettings.builtInSound, url: WaitingCue.defaultSoundURL)
                row("None", value: AppSettings.noSound, url: nil)
            }
            Section("System sounds") {
                if sounds.isEmpty {
                    Text("No system sounds found on this device.").foregroundStyle(.secondary)
                }
                ForEach(filtered) { sound in
                    row(sound.name, value: sound.url.path, url: sound.url)
                }
            }
        }
        .searchable(text: $query, prompt: "Search sounds")
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .task { sounds = await Task.detached { SystemSounds.all() }.value }
    }

    private var filtered: [SoundFile] {
        query.isEmpty ? sounds : sounds.filter { $0.name.localizedStandardContains(query) }
    }

    private func row(_ name: String, value: String, url: URL?) -> some View {
        Button {
            selection = value
            if let url { WaitingFeedback.playSound(at: url) }
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
