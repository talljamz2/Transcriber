import SwiftUI
import Speech

struct SettingsView: View {
    @AppStorage(SettingsKey.locale) private var localeIdentifier = ""
    @AppStorage(SettingsKey.captionSize) private var captionSize: Double = 32
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .system
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true
    @AppStorage(SettingsKey.autoSummarize) private var autoSummarize = true
    @Environment(CaptionController.self) private var controller

    @State private var languages: [LanguageOption] = []

    var body: some View {
        Form {
            Section {
                Picker("Spoken language", selection: $localeIdentifier) {
                    Text("Same as device").tag("")
                    ForEach(languages) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .disabled(controller.isRecording)
            } header: {
                Text("Captions")
            } footer: {
                Text("Speech is recognized on this device. The first time you use a language, its speech model downloads once.")
            }

            Section("Text") {
                Picker("Font", selection: $captionFont) {
                    Section("Serif") {
                        ForEach(CaptionFont.allCases.filter(\.isSerif)) { font in
                            Text(font.name).font(font.font(size: 17)).tag(font)
                        }
                    }
                    Section("Sans serif") {
                        ForEach(CaptionFont.allCases.filter { !$0.isSerif }) { font in
                            Text(font.name).font(font.font(size: 17)).tag(font)
                        }
                    }
                }
                Slider(value: $captionSize, in: 18...72, step: 2) {
                    Text("Caption text size")
                } minimumValueLabel: {
                    Text("A").font(.caption)
                } maximumValueLabel: {
                    Text("A").font(.title)
                }
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(captionFont.font(size: captionSize, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }

            Section {
                Toggle("Keep screen on while captioning", isOn: $keepAwake)
                Toggle("Summarize automatically when I stop", isOn: $autoSummarize)
            } footer: {
                Text(Summarizer.statusDescription)
            }

            Section("Microphone") {
                #if os(iOS)
                Text("Uses the iPhone's microphone, or a connected headset or AirPods microphone when one is connected.")
                #else
                Text("Uses the Mac's current input. Choose a different microphone in System Settings › Sound › Input.")
                #endif
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { await loadLanguages() }
    }

    private func loadLanguages() async {
        let locales = await SpeechTranscriber.supportedLocales
        languages = locales
            .map { locale in
                let id = locale.identifier(.bcp47)
                return LanguageOption(id: id, name: Locale.current.localizedString(forIdentifier: id) ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct LanguageOption: Identifiable {
    let id: String
    let name: String
}
