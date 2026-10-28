import SwiftUI

/// Results of searching every saved session: transcripts, summaries, actions and topics.
struct SearchResultsView: View {
    let sessions: [CaptionSession]
    let query: String

    private struct Result: Identifiable {
        let session: CaptionSession
        let snippet: String
        let place: String
        let count: Int
        var id: UUID { session.id }
    }

    private var results: [Result] {
        sessions.compactMap { session in
            let hits = session.segments.filter { $0.text.localizedStandardContains(query) }
            if let first = hits.first {
                return Result(session: session, snippet: Highlight.snippet(first.text, query: query),
                              place: hits.count == 1 ? "1 match in transcript" : "\(hits.count) matches in transcript",
                              count: hits.count)
            }
            if let action = session.actions.first(where: { $0.task.localizedStandardContains(query) }) {
                return Result(session: session, snippet: action.task, place: "In actions", count: 1)
            }
            let other = [session.title, session.oneLiner, session.summary] + session.topics
            if let text = other.first(where: { $0.localizedStandardContains(query) }) {
                return Result(session: session, snippet: Highlight.snippet(text, query: query), place: "In summary", count: 1)
            }
            return nil
        }
    }

    var body: some View {
        let results = results
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results) { result in
                NavigationLink(value: SavedRoute.match(result.session, query)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.session.displayTitle).font(.headline)
                        Text(Highlight.text(result.snippet, query: query))
                            .font(.subheadline)
                            .lineLimit(3)
                        Text("\(Format.day(result.session.day)), \(Format.time(result.session.startedAt)) · \(result.place)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
