import Foundation
import FoundationModels

/// Summarizes transcripts with Apple Intelligence's on-device model, falling back to a
/// simple word-frequency summary on devices without it.
@MainActor
enum Summarizer {
    static var statusDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Summaries are written on this device by Apple Intelligence."
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence, so summaries use a basic on-device method."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings for better summaries. Until then, a basic on-device method is used."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready (downloading). A basic summary is used until it's done."
        case .unavailable:
            return "Apple Intelligence isn't available, so summaries use a basic on-device method."
        }
    }

    static func summarize(_ session: CaptionSession) async {
        guard !session.segments.isEmpty else {
            session.summary = "Nothing was captured in this session."
            session.summarySource = ""
            return
        }
        guard case .available = SystemLanguageModel.default.availability else {
            session.summary = BasicSummary.make(for: session)
            session.summarySource = "local"
            return
        }
        do {
            let header = "Recorded \(Format.dateTime(session.startedAt)), lasting \(Format.duration(session.duration))."
            session.summary = try await summarizeOnDevice(session.transcriptText(withTimes: false), header: header)
            session.summarySource = "apple"
        } catch {
            session.summary = BasicSummary.make(for: session)
                + "\n\n## Note\nApple Intelligence couldn't summarize this transcript (\(error.localizedDescription)), so this is a basic summary."
            session.summarySource = "local"
        }
    }

    // MARK: - Apple Intelligence

    private static let summaryInstructions = """
    You summarize transcripts for a person with hearing loss who used live captions to follow a \
    conversation, meeting, lecture, or appointment. The transcript came from automatic speech \
    recognition: it has no speaker labels and may contain recognition errors. Infer the intended words \
    where the context makes them clear, and never invent details.

    Reply in the transcript's language using these Markdown sections, leaving out any that would be empty:
    ## Overview
    Two to four sentences on what it was about.
    ## Key points
    Bullets for the main things said or decided.
    ## Action items & details to remember
    Bullets for tasks, dates, times, names, numbers, places, and instructions.
    ## Possibly misheard
    Bullets for garbled passages where the meaning is uncertain, with your best guess.
    """

    private static let notesInstructions = """
    You condense part of a speech-recognition transcript into short bullet notes. Keep every task, \
    date, time, name, number, place, and instruction. Never invent details.
    """

    /// The on-device model has a small context window, so long transcripts are condensed in
    /// parts first and the notes are then summarized.
    private static func summarizeOnDevice(_ transcript: String, header: String, chunkSize: Int = 5000) async throws -> String {
        do {
            var text = transcript
            var condensed = false
            var rounds = 0
            while text.count > chunkSize && rounds < 4 {
                let parts = chunks(of: text, size: chunkSize)
                var notes: [String] = []
                for (i, part) in parts.enumerated() {
                    notes.append(try await respond(
                        to: "Part \(i + 1) of \(parts.count):\n\n\(part)",
                        instructions: notesInstructions
                    ))
                }
                text = notes.joined(separator: "\n")
                condensed = true
                rounds += 1
            }
            let label = condensed ? "Notes taken from the transcript" : "Transcript"
            return try await respond(
                to: "\(header)\n\n\(label):\n\n\(text)",
                instructions: summaryInstructions
            )
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error, chunkSize > 1000 {
                return try await summarizeOnDevice(transcript, header: header, chunkSize: chunkSize / 2)
            }
            throw error
        }
    }

    private static func respond(to prompt: String, instructions: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt).content
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

/// Picks the most representative sentences by word frequency. Used when Apple Intelligence isn't available.
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
