import Foundation
import SwiftData

struct Segment: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Date
    var text: String
}

/// What kind of recording a session is. Chosen automatically after each session.
enum SessionCategory: String, Codable, CaseIterable, Identifiable {
    case conversation
    case meeting
    case voiceNote
    case phoneCall
    case lecture
    case media

    var id: String { rawValue }

    var name: String {
        switch self {
        case .conversation: "Conversation"
        case .meeting: "Meeting"
        case .voiceNote: "Voice note"
        case .phoneCall: "Phone call"
        case .lecture: "Lecture / talk"
        case .media: "TV & media"
        }
    }

    var symbol: String {
        switch self {
        case .conversation: "person.2"
        case .meeting: "person.3"
        case .voiceNote: "waveform"
        case .phoneCall: "phone"
        case .lecture: "graduationcap"
        case .media: "tv"
        }
    }

    /// Media sessions are flagged for review and left out of daily summaries.
    var isLowValue: Bool { self == .media }
}

/// Something someone said they would do, or that needs doing.
struct ActionItem: Codable, Hashable, Identifiable {
    enum Owner: String, Codable {
        case me        // the person using the app
        case other     // someone else
        case unclear   // couldn't tell who
    }

    var id = UUID()
    var task: String
    var owner: Owner
    /// A name when someone else was named, e.g. "Sarah".
    var person: String = ""
    /// The deadline as spoken, e.g. "by next week". Empty if none.
    var due: String = ""
    /// The deadline as a date when it could be worked out.
    var dueDate: Date?
    /// The words from the transcript the action came from.
    var quote: String = ""
}

enum ProcessingState: String, Codable {
    case pending, processing, done, failed
}

@Model
final class CaptionSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var title: String = ""
    var localeIdentifier: String = ""
    var segments: [Segment] = []
    var summary: String = ""
    /// "apple" (Apple Intelligence), "local" (basic on-device summary), or "" (none yet).
    var summarySource: String = ""

    // Filled in automatically after each session.
    var categoryRaw: String = ""
    /// A one-line description, e.g. "Hockey game commentary".
    var oneLiner: String = ""
    /// The summary's overview paragraph on its own, used to build daily summaries.
    var overview: String = ""
    var actions: [ActionItem] = []
    var topics: [String] = []
    var processingRaw: String = "pending"
    /// Set when the user keeps a flagged session, so it leaves the Tidy-up list.
    var reviewed: Bool = false
    /// Set when the user picks the category themselves, so reprocessing doesn't overwrite it.
    var categoryChosenByUser: Bool = false
    /// Set once Apple Intelligence has written the title (until then it's the first few words).
    var hasSmartTitle: Bool = false
    /// Set when the user renames the session, so it's never retitled.
    var titleChosenByUser: Bool = false

    init(localeIdentifier: String) {
        self.localeIdentifier = localeIdentifier
    }
}

extension CaptionSession {
    var category: SessionCategory? {
        get { SessionCategory(rawValue: categoryRaw) }
        set { categoryRaw = newValue?.rawValue ?? "" }
    }

    var processing: ProcessingState {
        get { ProcessingState(rawValue: processingRaw) ?? .pending }
        set { processingRaw = newValue.rawValue }
    }

    var needsReview: Bool { (category?.isLowValue ?? false) && !reviewed }

    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var displayTitle: String { title.isEmpty ? "Untitled session" : title }

    var day: Date { Calendar.current.startOfDay(for: startedAt) }

    func transcriptText(withTimes: Bool) -> String {
        segments
            .map { withTimes ? "[\(Format.time($0.time))] \($0.text)" : $0.text }
            .joined(separator: "\n")
    }

    func exportText() -> String {
        var out = "\(displayTitle)\n\(Format.dateTime(startedAt)) (\(Format.duration(duration)))"
        if let category { out += " · \(category.name)" }
        out += "\n\n"
        if !actions.isEmpty {
            out += "ACTIONS\n" + actions.map { "- \($0.exportLine)" }.joined(separator: "\n") + "\n\n"
        }
        if !summary.isEmpty { out += "SUMMARY\n\(summary)\n\n" }
        out += "TRANSCRIPT\n\(transcriptText(withTimes: true))\n"
        return out
    }

    static func makeTitle(from text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let snippet = words.prefix(7).joined(separator: " ")
        return words.count > 7 ? snippet + "…" : snippet
    }
}

extension ActionItem {
    var ownerLabel: String {
        switch owner {
        case .me: "You"
        case .other: person.isEmpty ? "Someone else" : person
        case .unclear: "Unclear"
        }
    }

    var dueLabel: String {
        if let dueDate {
            let date = dueDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return due.isEmpty ? date : "\(due) (\(date))"
        }
        return due
    }

    var exportLine: String {
        var line = "[\(ownerLabel)] \(task)"
        if !dueLabel.isEmpty { line += " — \(dueLabel)" }
        return line
    }
}

/// A summary of everything recorded on one day.
@Model
final class DaySummary {
    var day: Date = Date()
    var brief: String = ""
    var themes: [String] = []
    var generatedAt: Date = Date()
    /// Fingerprint of the sessions the summary was built from, to tell when it's out of date.
    var sourceFingerprint: String = ""

    init(day: Date) {
        self.day = day
    }
}

/// Live text grouped into paragraphs, starting a new one after a pause.
struct CaptionParagraph: Identifiable {
    let id: Int
    let time: Date
    let text: String

    static func group(_ segments: [Segment], pause: TimeInterval = 4) -> [CaptionParagraph] {
        var result: [CaptionParagraph] = []
        var current: [String] = []
        var start: Date?
        var last: Date?
        for seg in segments {
            if let l = last, seg.time.timeIntervalSince(l) > pause, let s = start {
                result.append(CaptionParagraph(id: result.count, time: s, text: current.joined(separator: " ")))
                current = []
                start = nil
            }
            if start == nil { start = seg.time }
            current.append(seg.text)
            last = seg.time
        }
        if let s = start {
            result.append(CaptionParagraph(id: result.count, time: s, text: current.joined(separator: " ")))
        }
        return result
    }
}

enum Format {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func duration(_ interval: TimeInterval) -> String {
        let mins = Int((interval / 60).rounded())
        if mins < 1 { return "under a minute" }
        if mins < 60 { return "\(mins) min" }
        return "\(mins / 60) h \(mins % 60) min"
    }
}
