import Foundation
import SwiftData

struct Segment: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Date
    var text: String
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
    /// "apple" (Apple Intelligence), "local" (on-device word-frequency summary), or "" (none yet).
    var summarySource: String = ""

    init(localeIdentifier: String) {
        self.localeIdentifier = localeIdentifier
    }
}

extension CaptionSession {
    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var displayTitle: String { title.isEmpty ? "Untitled session" : title }

    func transcriptText(withTimes: Bool) -> String {
        segments
            .map { withTimes ? "[\(Format.time($0.time))] \($0.text)" : $0.text }
            .joined(separator: "\n")
    }

    func exportText() -> String {
        var out = "\(displayTitle)\n\(Format.dateTime(startedAt)) (\(Format.duration(duration)))\n\n"
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

    static func duration(_ interval: TimeInterval) -> String {
        let mins = Int((interval / 60).rounded())
        if mins < 1 { return "under a minute" }
        if mins < 60 { return "\(mins) min" }
        return "\(mins / 60) h \(mins % 60) min"
    }
}
