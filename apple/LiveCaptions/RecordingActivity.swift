import Foundation
#if os(iOS)
import ActivityKit

/// Shows the running session on the Lock Screen and in the Dynamic Island.
@MainActor
enum RecordingActivity {
    private static var activity: Activity<RecordingActivityAttributes>?

    static func start(startedAt: Date, quietly: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        activity = try? Activity.request(
            attributes: RecordingActivityAttributes(startedAt: startedAt, quietly: quietly),
            content: ActivityContent(state: .init(latest: "", isPaused: false), staleDate: nil)
        )
    }

    static func update(latest: String, paused: Bool) {
        guard let activity else { return }
        let state = RecordingActivityAttributes.ContentState(latest: String(latest.suffix(160)), isPaused: paused)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    static func end() {
        guard let finished = activity else { return }
        activity = nil
        Task { await finished.end(nil, dismissalPolicy: .immediate) }
    }
}
#else
/// Live Activities are iPhone and iPad only.
@MainActor
enum RecordingActivity {
    static func start(startedAt: Date, quietly: Bool) {}
    static func update(latest: String, paused: Bool) {}
    static func end() {}
}
#endif
