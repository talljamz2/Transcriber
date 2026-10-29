import Foundation
import FoundationModels

// MARK: - Shapes Apple Intelligence fills in

@Generable
enum GeneratedCategory {
    case conversation
    case meeting
    case voiceNote
    case phoneCall
    case lecture
    case media
}

@Generable
struct GeneratedClassification {
    @Guide(description: "A short title of 2 to 6 words, like a calendar entry or a note's title. Name the subject, not the first words said. For example: 'Q3 budget review', 'Doctor's appointment', 'Leafs vs. Canadiens', 'Plumber and grocery reminders'.")
    var title: String
    @Guide(description: "The kind of recording.")
    var category: GeneratedCategory
    @Guide(description: "What the recording is, in under 12 words. For example: 'Hockey game commentary', 'Team meeting about the Q3 budget', 'Note about groceries and calling the plumber'.")
    var label: String
}

@Generable
enum GeneratedOwner {
    case speakerSelf
    case namedPerson
    case unspecified
}

@Generable
struct GeneratedAction {
    @Guide(description: "The task, starting with a verb. For example: 'Send Sarah the revised budget'.")
    var task: String
    @Guide(description: "speakerSelf when a speaker says they will do it themselves ('I'll…', 'I will…', 'let me…', 'I need to…'); namedPerson when a specific person is named as responsible; otherwise unspecified.")
    var owner: GeneratedOwner
    @Guide(description: "The responsible person's name when owner is namedPerson, otherwise empty.")
    var person: String
    @Guide(description: "The deadline as said, for example 'by next Friday'. Empty if none.")
    var due: String
    @Guide(description: "The deadline as a date in YYYY-MM-DD format, worked out from the recording date. Empty if there is no deadline or it can't be worked out.")
    var dueDate: String
    @Guide(description: "The short phrase from the transcript this action comes from.")
    var quote: String
}

@Generable
struct GeneratedDigest {
    @Guide(description: "Two to four sentences on what it was about.")
    var overview: String
    @Guide(description: "The main things said or learned.")
    var keyPoints: [String]
    @Guide(description: "Decisions that were made. Empty if none.")
    var decisions: [String]
    @Guide(description: "Every task, promise, request, reminder, or next step mentioned. Empty if none.")
    var actions: [GeneratedAction]
    @Guide(description: "One to five short topic keywords.")
    var topics: [String]
    @Guide(description: "Passages that look misrecognized, with a best guess at what was meant. Empty if none.")
    var possiblyMisheard: [String]
}

@Generable
struct GeneratedDayBrief {
    @Guide(description: "Two to four sentences summarizing the person's day.")
    var brief: String
    @Guide(description: "Ideas or subjects that came up more than once or stood out. Empty if none.")
    var themes: [String]
}

// MARK: - Processing

/// Categorizes each session, summarizes it and pulls out actions, using Apple Intelligence on the
/// device. Falls back to a basic word-frequency summary on devices without it.
@MainActor
enum SessionProcessor {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var statusDescription: String {
        if ClaudeSummarizer.isEnabled {
            return "Sessions are titled and sorted on this device, and summarized by \(ClaudeSummarizer.model.name)."
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Every session is sorted and summarized on this device by Apple Intelligence."
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence, so sessions get a basic summary and aren't sorted into categories."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings so sessions can be sorted and summarized. Until then, a basic summary is used."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Sessions will be sorted and summarized once it's ready."
        case .unavailable:
            return "Apple Intelligence isn't available, so sessions get a basic summary."
        }
    }

    /// Fills in category, summary, actions and topics. TV & media sessions only get a category and a
    /// one-line description unless `full` is set (the user asked for a summary).
    static func process(_ session: CaptionSession, full: Bool = false) async {
        guard !session.segments.isEmpty else {
            session.processing = .done
            return
        }
        let useClaude = ClaudeSummarizer.isEnabled
        guard isAvailable || useClaude else {
            session.summary = BasicSummary.make(for: session)
            session.summarySource = "local"
            session.processing = .done
            return
        }

        session.processing = .processing
        let text = session.transcriptText(withTimes: false)
        do {
            // Titles and categories are quick and free on the device.
            if isAvailable, session.category == nil || session.oneLiner.isEmpty || !session.hasSmartTitle {
                let result = try await classify(text)
                if !session.categoryChosenByUser { session.category = SessionCategory(result.category) }
                session.oneLiner = result.label
                applyTitle(result.title, to: session)
            }
            if session.category?.isLowValue == true && !full {
                session.processing = .done
                return
            }

            var claudeError: Error?
            if useClaude {
                do {
                    let digest = try await ClaudeSummarizer.digest(transcript: text, header: header(for: session))
                    if !isAvailable || session.category == nil {
                        if !session.categoryChosenByUser, let category = SessionCategory(rawValue: digest.category) {
                            session.category = category
                        }
                        if session.oneLiner.isEmpty { session.oneLiner = digest.label }
                        applyTitle(digest.title, to: session)
                    }
                    apply(SummaryParts(digest), to: session, source: "claude")
                    session.processing = .done
                    return
                } catch {
                    claudeError = error
                }
            }

            guard isAvailable else { throw claudeError ?? ClaudeSummarizer.Failure.empty }
            let digest = try await summarize(text, session: session)
            apply(SummaryParts(digest), to: session, source: "apple")
            if let claudeError {
                session.summary += "\n## Note\nWritten by Apple Intelligence because Claude wasn't reachable (\(claudeError.localizedDescription)). Tap Summarize again to retry with Claude.\n"
            }
            session.processing = .done
        } catch {
            session.summary = BasicSummary.make(for: session)
                + "\n\n## Note\nThe summary couldn't be written (\(error.localizedDescription)), so this is a basic summary. Tap Summarize again to retry."
            session.summarySource = "local"
            session.processing = .failed
        }
    }

    private static func header(for session: CaptionSession) -> String {
        """
        Recorded on \(session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year())) \
        at \(Format.time(session.startedAt)), lasting \(Format.duration(session.duration)). \
        Kind of recording: \(session.category?.name ?? "unknown").
        """
    }

    /// A short overview of a day, built from its sessions' summaries.
    static func summarizeDay(_ sessions: [CaptionSession]) async -> (brief: String, themes: [String]) {
        guard !sessions.isEmpty else { return (basicDayBrief(sessions), []) }
        if ClaudeSummarizer.isEnabled {
            let detail = sessions.map { s in
                var block = "• \(Format.time(s.startedAt)) — \(s.category?.name ?? "Recording"): \(s.displayTitle)"
                if !s.overview.isEmpty { block += "\n  \(s.overview)" }
                for action in s.actions { block += "\n  Action [\(action.ownerLabel)]: \(action.task)\(action.due.isEmpty ? "" : " (\(action.due))")" }
                return block
            }.joined(separator: "\n")
            if let result = try? await ClaudeSummarizer.dayBrief(dayName: Format.day(sessions[0].day), sessions: detail) {
                return result
            }
        }
        guard isAvailable else { return (basicDayBrief(sessions), []) }

        func lines(detailed: Bool) -> String {
            sessions.map { s in
                var line = "• \(Format.time(s.startedAt)) — \(s.category?.name ?? "Recording"): \(s.oneLiner.isEmpty ? s.displayTitle : s.oneLiner)"
                if detailed, !s.overview.isEmpty { line += ". \(s.overview.prefix(300))" }
                return line
            }.joined(separator: "\n")
        }
        var input = lines(detailed: true)
        if input.count > 3500 { input = lines(detailed: false) }
        if input.count > 3500 { input = String(input.prefix(3500)) }

        do {
            let session = LanguageModelSession(instructions: """
            You write a short end-of-day recap for a person with hearing loss who records their meetings, \
            conversations, lectures and voice notes. Write to them as "you". Never invent details.
            """)
            let result = try await session.respond(
                to: "Here is what was recorded on \(Format.day(sessions[0].day)):\n\n\(input)",
                generating: GeneratedDayBrief.self
            ).content
            return (result.brief, result.themes)
        } catch {
            return (basicDayBrief(sessions), [])
        }
    }

    /// Gives a session that was saved before smart titles a proper title, without re-summarizing it.
    static func retitle(_ session: CaptionSession) async {
        guard isAvailable, !session.segments.isEmpty, !session.hasSmartTitle else { return }
        if let result = try? await classify(session.transcriptText(withTimes: false)) {
            applyTitle(result.title, to: session)
            if session.oneLiner.isEmpty { session.oneLiner = result.label }
        }
    }

    private static func applyTitle(_ title: String, to session: CaptionSession) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
        guard !title.isEmpty else { return }
        if !session.titleChosenByUser { session.title = title }
        session.hasSmartTitle = true
    }

    // MARK: Classification

    private static let classifyInstructions = """
    You sort transcripts made by live speech recognition (no speaker labels, some recognition errors) into one category:
    - conversation: informal back-and-forth between people in person.
    - meeting: an organized discussion about work, plans, or decisions, often with several people.
    - voiceNote: one person talking to themselves: notes, reminders, ideas, to-dos, dictation, journaling.
    - phoneCall: a phone or video call.
    - lecture: one main speaker presenting to listeners: a class, talk, sermon, conference session, tour, or presentation.
    - media: TV, film, sports commentary, news broadcasts, podcasts, radio, online videos, music, or ads.
    """

    private static func classify(_ text: String) async throws -> GeneratedClassification {
        let session = LanguageModelSession(instructions: classifyInstructions)
        return try await session.respond(
            to: "Transcript:\n\n\(sample(text, limit: 3000))",
            generating: GeneratedClassification.self
        ).content
    }

    /// The start, middle and end of a long transcript, enough to tell what kind of recording it is.
    private static func sample(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let part = limit / 3
        let midStart = text.index(text.startIndex, offsetBy: text.count / 2 - part / 2)
        return "\(text.prefix(part)) … \(text[midStart...].prefix(part)) … \(text.suffix(part))"
    }

    // MARK: Summaries

    private static func summaryInstructions(for session: CaptionSession) -> String {
        var text = """
        You summarize transcripts for a person with hearing loss who used live captions. The transcript came \
        from automatic speech recognition: it has no speaker labels and may contain recognition errors. Infer \
        the intended words where the context makes them clear, and never invent details. Be thorough about \
        actions: include every promise ("I'll send it"), request ("can you…"), reminder, and next step, with \
        any deadline. Write in the transcript's language.
        """
        if session.category == .voiceNote {
            text += " This is the person's own voice note, so tasks mentioned are their own."
        }
        return text
    }

    private static let notesInstructions = """
    You condense part of a speech-recognition transcript into short bullet notes. Keep every task, promise, \
    request, deadline, date, time, name, number, place, and decision, and keep the exact wording of \
    promises like "I'll do X by Friday". Never invent details.
    """

    /// The on-device model has a small context window, so long transcripts are condensed in parts first.
    private static func summarize(_ transcript: String, session: CaptionSession, chunkSize: Int = 4000) async throws -> GeneratedDigest {
        do {
            var text = transcript
            var condensed = false
            var rounds = 0
            while text.count > chunkSize && rounds < 4 {
                let parts = chunks(of: text, size: chunkSize)
                var notes: [String] = []
                for (i, part) in parts.enumerated() {
                    let s = LanguageModelSession(instructions: notesInstructions)
                    notes.append(try await s.respond(to: "Part \(i + 1) of \(parts.count):\n\n\(part)").content)
                }
                text = notes.joined(separator: "\n")
                condensed = true
                rounds += 1
            }
            let header = """
            Recorded on \(session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year())) \
            at \(Format.time(session.startedAt)), lasting \(Format.duration(session.duration)). \
            Kind of recording: \(session.category?.name ?? "unknown").
            """
            let label = condensed ? "Notes taken from the transcript" : "Transcript"
            let s = LanguageModelSession(instructions: summaryInstructions(for: session))
            return try await s.respond(to: "\(header)\n\n\(label):\n\n\(text)", generating: GeneratedDigest.self).content
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error, chunkSize > 1000 {
                return try await summarize(transcript, session: session, chunkSize: chunkSize / 2)
            }
            throw error
        }
    }

    private static func apply(_ parts: SummaryParts, to session: CaptionSession, source: String) {
        var markdown = "## Overview\n\(parts.overview)\n"
        func section(_ title: String, _ items: [String]) {
            let items = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !items.isEmpty else { return }
            markdown += "\n## \(title)\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        section("Key points", parts.keyPoints)
        section("Decisions", parts.decisions)
        section("Possibly misheard", parts.possiblyMisheard)

        session.overview = parts.overview
        session.summary = markdown
        session.summarySource = source
        session.topics = parts.topics
        session.actions = parts.actions.compactMap { action(from: $0, in: session) }
    }

    private static func action(from draft: SummaryParts.Action, in session: CaptionSession) -> ActionItem? {
        let task = draft.task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return nil }
        let isOwnNote = session.category == .voiceNote
        let person = draft.person.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner: ActionItem.Owner
        switch draft.kind {
        case .speakerSelf, .unspecified:
            // Without speaker labels, "I'll do it" in a conversation could be anyone.
            owner = isOwnNote ? .me : .unclear
        case .namedPerson:
            owner = person.isEmpty ? .unclear : .other
        }
        return ActionItem(
            task: task,
            owner: owner,
            person: owner == .other ? person : "",
            due: draft.due.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: parseDate(draft.dueDate),
            quote: draft.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    private static func basicDayBrief(_ sessions: [CaptionSession]) -> String {
        guard !sessions.isEmpty else { return "Nothing was recorded on this day." }
        return "You recorded " + DayStats(sessions).description + "."
    }

    /// Splits text into pieces of at most `size` characters, breaking at sentence or word boundaries.
    private static func chunks(of text: String, size: Int) -> [String] {
        var result: [String] = []
        var remaining = Substring(text)
        while remaining.count > size {
            let limit = remaining.index(remaining.startIndex, offsetBy: size)
            let window = remaining[..<limit]
            var cut = window.lastIndex(where: { ".!?\n".contains($0) }).map { remaining.index(after: $0) }
                ?? window.lastIndex(where: \.isWhitespace)
                ?? limit
            if cut <= remaining.startIndex { cut = limit }
            let piece = remaining[..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            remaining = remaining[cut...]
        }
        let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }
}

/// A summary in one shape, whichever model wrote it.
struct SummaryParts {
    struct Action {
        enum Kind { case speakerSelf, namedPerson, unspecified }
        var task: String
        var kind: Kind
        var person: String
        var due: String
        var dueDate: String
        var quote: String
    }

    var overview: String
    var keyPoints: [String]
    var decisions: [String]
    var possiblyMisheard: [String]
    var topics: [String]
    var actions: [Action]

    init(_ digest: GeneratedDigest) {
        overview = digest.overview
        keyPoints = digest.keyPoints
        decisions = digest.decisions
        possiblyMisheard = digest.possiblyMisheard
        topics = digest.topics
        actions = digest.actions.map { a in
            let kind: Action.Kind
            switch a.owner {
            case .speakerSelf: kind = .speakerSelf
            case .namedPerson: kind = .namedPerson
            case .unspecified: kind = .unspecified
            }
            return Action(task: a.task, kind: kind, person: a.person, due: a.due, dueDate: a.dueDate, quote: a.quote)
        }
    }

    init(_ digest: ClaudeSummarizer.Digest) {
        overview = digest.overview
        keyPoints = digest.keyPoints
        decisions = digest.decisions
        possiblyMisheard = digest.possiblyMisheard
        topics = digest.topics
        actions = digest.actions.map { a in
            let kind: Action.Kind = switch a.owner {
            case "speaker_self": .speakerSelf
            case "named_person": .namedPerson
            default: .unspecified
            }
            return Action(task: a.task, kind: kind, person: a.person, due: a.due, dueDate: a.dueDate, quote: a.quote)
        }
    }
}

extension SessionCategory {
    init(_ generated: GeneratedCategory) {
        switch generated {
        case .conversation: self = .conversation
        case .meeting: self = .meeting
        case .voiceNote: self = .voiceNote
        case .phoneCall: self = .phoneCall
        case .lecture: self = .lecture
        case .media: self = .media
        }
    }
}

/// Counts of a day's sessions by category, e.g. "2 meetings, 1 lecture and 4 voice notes".
struct DayStats: CustomStringConvertible {
    let counts: [(SessionCategory?, Int)]

    init(_ sessions: [CaptionSession]) {
        var byCategory: [String: Int] = [:]
        for s in sessions { byCategory[s.categoryRaw, default: 0] += 1 }
        let order: [SessionCategory?] = SessionCategory.allCases.map { $0 } + [nil]
        counts = order.compactMap { cat in
            let n = byCategory[cat?.rawValue ?? ""] ?? 0
            return n > 0 ? (cat, n) : nil
        }
    }

    var description: String {
        let parts = counts.map { cat, n -> String in
            let noun: String
            switch cat {
            case .conversation: noun = n == 1 ? "conversation" : "conversations"
            case .meeting: noun = n == 1 ? "meeting" : "meetings"
            case .voiceNote: noun = n == 1 ? "voice note" : "voice notes"
            case .phoneCall: noun = n == 1 ? "call" : "calls"
            case .lecture: noun = n == 1 ? "lecture or talk" : "lectures or talks"
            case .media: noun = n == 1 ? "TV or media session" : "TV or media sessions"
            case nil: noun = n == 1 ? "recording" : "recordings"
            }
            return "\(n) \(noun)"
        }
        guard parts.count > 1 else { return parts.first ?? "nothing" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}

enum BasicSummary {
    private static let stopwords: Set<String> = Set("""
    a an the and or but if then so of to in on at for with from by as is are was were be been being it its \
    this that these those i you he she we they me him her us them my your his our their what which who whom \
    do does did have has had not no yes just like um uh okay ok yeah oh well really very can could would \
    should will shall may might there here about into out up down over all any some get got go going know \
    think say said
    """.split(separator: " ").map(String.init))

    static func make(for session: CaptionSession) -> String {
        let text = session.transcriptText(withTimes: false)
        let sentences = splitSentences(text).filter { $0.split(whereSeparator: \.isWhitespace).count >= 4 }
        var out = "## Overview\nBasic on-device summary (\(session.wordCount) words over \(Format.duration(session.duration))).\n"
        if sentences.count <= 5 {
            if !sentences.isEmpty {
                out += "\n## Key points\n" + sentences.map { "- \($0)" }.joined(separator: "\n")
            }
            return out
        }

        var freq: [String: Int] = [:]
        for word in words(in: text) where word.count > 2 && !stopwords.contains(word) {
            freq[word, default: 0] += 1
        }
        let scored = sentences.enumerated().map { index, sentence -> (Int, String, Double) in
            let toks = words(in: sentence)
            let total = toks.reduce(0) { $0 + (freq[$1] ?? 0) }
            return (index, sentence, Double(total) / max(1, Double(toks.count)).squareRoot())
        }
        let count = min(8, max(3, Int((Double(sentences.count) / 10).rounded())))
        let top = scored.sorted { $0.2 > $1.2 }.prefix(count).sorted { $0.0 < $1.0 }
        let topics = freq.sorted { $0.value > $1.value }.prefix(8).map(\.key)

        out += "\n## Frequent topics\n- \(topics.joined(separator: ", "))\n"
        out += "\n## Key points\n" + top.map { "- \($0.1)" }.joined(separator: "\n")
        return out
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            for line in (sub ?? "").split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
            }
        }
        return sentences
    }
}
