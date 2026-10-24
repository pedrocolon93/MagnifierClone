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
                Section("Waiting sound") {
                    VStack(alignment: .leading) {
                        Text("Interval: \(settings.waitInterval.formatted(.number.precision(.fractionLength(1)))) s")
                        Slider(value: $settings.waitInterval, in: AppSettings.waitIntervalRange, step: 0.5)
                            .accessibilityLabel("Waiting sound interval")
                            .accessibilityValue("\(settings.waitInterval.formatted(.number.precision(.fractionLength(1)))) seconds")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
