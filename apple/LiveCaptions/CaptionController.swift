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
    static let eveningReminder = "eveningReminder"
    /// Minutes after midnight, e.g. 1200 for 8:00 PM.
    static let reminderMinutes = "reminderMinutes"
}

/// Ties a live transcriber to saved sessions: records and saves them, then sorts and summarizes
/// them in the background, builds daily summaries, and keeps the evening reminder up to date.
@MainActor
@Observable
final class CaptionController {
    let transcriber = LiveTranscriber()
    /// The session shown on the Live tab (the one recording, or the last one recorded).
    private(set) var current: CaptionSession?
    private(set) var status = "Tap Start to begin captioning."
    private(set) var errorMessage: String?
    /// Days whose summary is being built right now.
    private(set) var buildingDays: Set<Date> = []

    private let context: ModelContext
    private var queue: [(session: CaptionSession, full: Bool)] = []
    private var worker: Task<Void, Never>?
    #if os(macOS)
    private var awakeActivity: NSObjectProtocol?
    #endif

    var isRecording: Bool { transcriber.phase == .listening }

    init(context: ModelContext) {
        self.context = context
        transcriber.onFinal = { [weak self] text in self?.append(text) }
    }

    // MARK: - Recording

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
        session.processing = .pending
        save()
        status = "Saved. Sorting and summarizing in the background."
        enqueue(session)
        await EveningReminder.requestPermissionIfNeeded()
    }

    private func append(_ text: String) {
        guard let session = current else { return }
        // Insert on the first words so empty sessions are never saved.
        if session.modelContext == nil { context.insert(session) }
        session.segments.append(Segment(time: .now, text: text))
        session.endedAt = .now
        if session.title.isEmpty { session.title = CaptionSession.makeTitle(from: text) }
    }

    // MARK: - Background processing

    /// Picks up sessions that weren't finished, e.g. because the app was closed mid-way.
    func resumePendingWork() {
        let pending = ProcessingState.pending.rawValue
        let processing = ProcessingState.processing.rawValue
        let descriptor = FetchDescriptor<CaptionSession>(
            predicate: #Predicate { $0.processingRaw == pending || $0.processingRaw == processing },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        for session in (try? context.fetch(descriptor)) ?? [] where !isLive(session) {
            enqueue(session)
        }
        Task { await EveningReminder.update(context: context) }
    }

    /// Re-summarizes a session in full (also used for TV & media sessions on request).
    func summarize(_ session: CaptionSession) {
        session.processing = .pending
        enqueue(session, full: true)
    }

    func isQueued(_ session: CaptionSession) -> Bool {
        session.processing == .pending || session.processing == .processing
    }

    private func enqueue(_ session: CaptionSession, full: Bool = false) {
        if let index = queue.firstIndex(where: { $0.session.id == session.id }) {
            queue[index].full = queue[index].full || full
        } else {
            queue.append((session, full))
        }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let job = self?.nextJob() {
                await SessionProcessor.process(job.session, full: job.full)
                self?.save()
                await self?.refreshReminder()
            }
            self?.worker = nil
        }
    }

    private func nextJob() -> (session: CaptionSession, full: Bool)? {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            if !job.session.isDeleted, job.session.modelContext != nil { return job }
        }
        return nil
    }

    // MARK: - Editing

    func setCategory(_ category: SessionCategory, for session: CaptionSession) {
        session.category = category
        session.categoryChosenByUser = true
        session.reviewed = false
        // A session moved out of TV & media deserves a full summary if it doesn't have one.
        if !category.isLowValue && session.summarySource != "apple" && !isLive(session) {
            summarize(session)
        }
        changed()
    }

    func setOwner(_ owner: ActionItem.Owner, for actionID: UUID, in session: CaptionSession) {
        guard let index = session.actions.firstIndex(where: { $0.id == actionID }) else { return }
        var actions = session.actions
        actions[index].owner = owner
        session.actions = actions
        save()
    }

    func keep(_ session: CaptionSession) {
        session.reviewed = true
        changed()
    }

    func delete(_ sessions: [CaptionSession]) {
        for session in sessions where !isLive(session) {
            context.delete(session)
        }
        changed()
    }

    func isLive(_ session: CaptionSession) -> Bool {
        isRecording && current?.id == session.id
    }

    private func changed() {
        save()
        Task { await refreshReminder() }
    }

    // MARK: - Daily summaries

    func daySummary(for day: Date) -> DaySummary? {
        let descriptor = FetchDescriptor<DaySummary>(predicate: #Predicate { $0.day == day })
        return try? context.fetch(descriptor).first
    }

    /// The sessions that count toward a day's summary (everything except TV & media).
    func usefulSessions(on day: Date) -> [CaptionSession] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let descriptor = FetchDescriptor<CaptionSession>(
            predicate: #Predicate { $0.startedAt >= day && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { !($0.category?.isLowValue ?? false) && !isLive($0) }
    }

    func isDaySummaryStale(_ day: Date) -> Bool {
        daySummary(for: day)?.sourceFingerprint != fingerprint(usefulSessions(on: day))
    }

    /// Builds (or refreshes) a day's summary, first finishing any of the day's sessions still waiting.
    func buildDaySummary(for day: Date) async {
        guard !buildingDays.contains(day) else { return }
        buildingDays.insert(day)
        defer { buildingDays.remove(day) }

        // Wait (up to 10 minutes) for the day's sessions to be sorted and summarized.
        let deadline = Date.now.addingTimeInterval(600)
        while usefulSessions(on: day).contains(where: isQueued), Date.now < deadline {
            for session in usefulSessions(on: day) where session.processing == .pending {
                enqueue(session)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        let sessions = usefulSessions(on: day)
        let summary = daySummary(for: day) ?? {
            let new = DaySummary(day: day)
            context.insert(new)
            return new
        }()
        let result = await SessionProcessor.summarizeDay(sessions)
        summary.brief = result.brief
        summary.themes = result.themes
        summary.generatedAt = .now
        summary.sourceFingerprint = fingerprint(sessions)
        changed()
    }

    private func fingerprint(_ sessions: [CaptionSession]) -> String {
        sessions.map { "\($0.id.uuidString):\($0.summary.count):\($0.categoryRaw)" }.joined(separator: "|")
    }

    // MARK: - Helpers

    func refreshReminder() async {
        await EveningReminder.update(context: context)
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
