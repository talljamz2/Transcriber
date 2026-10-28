import Foundation
import SwiftData
import Observation
#if os(iOS)
import UIKit
#endif

enum SettingsKey {
    static let locale = "localeIdentifier"
    static let captionSize = "captionSize"
    static let captionFont = "captionFont"
    static let keepAwake = "keepScreenOn"
    static let autoSummarize = "autoSummarize"
}

/// Ties a live transcriber to a saved session: records, saves, and summarizes.
@MainActor
@Observable
final class CaptionController {
    let transcriber = LiveTranscriber()
    /// The session shown on the Live tab (the one recording, or the last one recorded).
    private(set) var current: CaptionSession?
    private(set) var status = "Tap Start to begin captioning."
    private(set) var errorMessage: String?
    private(set) var isSummarizing = false

    private let context: ModelContext
    #if os(macOS)
    private var awakeActivity: NSObjectProtocol?
    #endif

    var isRecording: Bool { transcriber.phase == .listening }

    init(context: ModelContext) {
        self.context = context
        transcriber.onFinal = { [weak self] text in self?.append(text) }
    }

    func start() async {
        errorMessage = nil
        let localeID = UserDefaults.standard.string(forKey: SettingsKey.locale) ?? ""
        current = CaptionSession(localeIdentifier: localeID)
        do {
            try await transcriber.start(localeIdentifier: localeID)
            current?.startedAt = .now
            status = "Listening…"
            setKeepAwake(UserDefaults.standard.object(forKey: SettingsKey.keepAwake) as? Bool ?? true)
        } catch {
            current = nil
            errorMessage = error.localizedDescription
            status = ""
        }
    }

    func stop() async {
        await transcriber.stop()
        setKeepAwake(false)
        guard let session = current else { return }

        if session.segments.isEmpty {
            status = "Stopped. Nothing was captured, so nothing was saved."
            return
        }
        session.endedAt = .now
        save()

        if UserDefaults.standard.object(forKey: SettingsKey.autoSummarize) as? Bool ?? true {
            status = "Saved. Writing summary…"
            await summarize(session)
            status = "Saved and summarized. Open the Saved tab to read it."
        } else {
            status = "Saved. Open the Saved tab to read or summarize it."
        }
    }

    func summarize(_ session: CaptionSession) async {
        isSummarizing = true
        defer { isSummarizing = false }
        await Summarizer.summarize(session)
        save()
    }

    private func append(_ text: String) {
        guard let session = current else { return }
        // Insert on the first words so empty sessions are never saved.
        if session.modelContext == nil { context.insert(session) }
        session.segments.append(Segment(time: .now, text: text))
        session.endedAt = .now
        if session.title.isEmpty { session.title = CaptionSession.makeTitle(from: text) }
    }

    private func save() {
        try? context.save()
    }

    private func setKeepAwake(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #else
        if on, awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "Showing live captions"
            )
        } else if !on, let activity = awakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            awakeActivity = nil
        }
        #endif
    }
}
