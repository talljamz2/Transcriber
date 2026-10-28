import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LiveCaptionsWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}

/// The Lock Screen banner and Dynamic Island while a session is running: a timer, the latest
/// words, and Pause / Resume / End buttons.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenView(context: context)
                .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusLabel(paused: context.state.isPaused)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Elapsed(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        LatestWords(text: context.state.latest)
                        Controls(paused: context.state.isPaused)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "waveform")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Elapsed(context: context)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(.red)
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusLabel(paused: context.state.isPaused)
                Spacer()
                Elapsed(context: context)
            }
            LatestWords(text: context.state.latest)
            Controls(paused: context.state.isPaused)
        }
    }
}

private struct StatusLabel: View {
    let paused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(paused ? Color.secondary : Color.red).frame(width: 8, height: 8)
            Text(paused ? "Paused" : "Recording").font(.headline)
        }
    }
}

private struct Elapsed: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        if context.state.isPaused {
            Text("Paused").foregroundStyle(.secondary)
        } else {
            Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LatestWords: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "Listening…" : text)
            .font(.system(.body, design: .serif))
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Controls: View {
    let paused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if paused {
                Button(intent: ResumeRecordingIntent()) {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button(intent: PauseRecordingIntent()) {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
            Button(intent: EndRecordingIntent()) {
                Label("End", systemImage: "stop.fill")
            }
            .tint(.red)
        }
        .buttonStyle(.bordered)
        .font(.subheadline.weight(.semibold))
    }
}
