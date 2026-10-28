import Foundation
import AppIntents
#if os(iOS)
import ActivityKit
#endif

/// Hooks the app fills in so the Live Activity's buttons can reach it. This file is also built
/// into the widget extension, which only draws the Live Activity; the buttons always run in the app.
@MainActor
enum RecordingControls {
    static var pause: (() async -> Void)?
    static var resume: (() async -> Void)?
    static var end: (() async -> Void)?
}

#if os(iOS)
/// What the Lock Screen and Dynamic Island show while a session is running.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The most recent words, so they can be read without unlocking.
        var latest: String
        var isPaused: Bool
    }

    var startedAt: Date
    /// Started from the Action Button, without opening the app.
    var quietly: Bool
}

struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause recording"

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingControls.pause?()
        return .result()
    }
}

struct ResumeRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume recording"

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingControls.resume?()
        return .result()
    }
}

struct EndRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End recording"

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingControls.end?()
        return .result()
    }
}
#endif
