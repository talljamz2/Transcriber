#if os(iOS)
import AppIntents

/// For the Action Button: press once to start recording quietly in the background (the phone can
/// stay locked), press again to end and save. Assign it in Settings › Action Button › Shortcut.
struct QuietRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Quiet recording"
    static let description = IntentDescription(
        "Starts recording and transcribing in the background, or ends and saves the current recording."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let controller = CaptionController.shared else { return .result() }
        if controller.isSessionActive {
            await controller.end()
        } else {
            await controller.start(quietly: true)
        }
        return .result()
    }
}

struct LiveCaptionsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuietRecordingIntent(),
            phrases: [
                "Start a recording in \(.applicationName)",
                "Record with \(.applicationName)",
            ],
            shortTitle: "Quiet recording",
            systemImageName: "waveform"
        )
    }
}
#endif
