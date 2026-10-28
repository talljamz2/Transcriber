import SwiftUI

/// The full transcript in normal reading order, with Find: matches are highlighted and the arrows
/// jump between them. Used from the Live screen (while recording) and from saved sessions.
struct TranscriptSearchView: View {
    let session: CaptionSession?
    var initialQuery = ""
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .newYork
    @State private var query = ""
    @State private var matchIndex = 0

    private var segments: [Segment] { session?.segments ?? [] }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [UUID] {
        guard !trimmedQuery.isEmpty else { return [] }
        return segments.filter { $0.text.localizedStandardContains(trimmedQuery) }.map(\.id)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if segments.isEmpty {
                            Text("Nothing has been said yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 200)
                        }
                        ForEach(segments) { segment in
                            row(segment)
                                .id(segment.id)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .background(Theme.sheet)
                .onChange(of: trimmedQuery) {
                    matchIndex = max(0, matches.count - 1)
                    scroll(proxy)
                }
                .onChange(of: matchIndex) { scroll(proxy) }
            }
            .navigationTitle("Transcript")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, placement: searchPlacement, prompt: "Find in transcript")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !trimmedQuery.isEmpty {
                    ToolbarItemGroup(placement: findBarPlacement) {
                        Text(matches.isEmpty ? "No matches" : "\(matchIndex + 1) of \(matches.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { step(-1) } label: { Image(systemName: "chevron.up") }
                            .disabled(matches.count < 2)
                            .accessibilityLabel("Previous match")
                        Button { step(1) } label: { Image(systemName: "chevron.down") }
                            .disabled(matches.count < 2)
                            .accessibilityLabel("Next match")
                    }
                }
            }
        }
        .presentationBackground(Theme.sheet)
        .onAppear { if query.isEmpty { query = initialQuery } }
    }

    /// Keep the find field visible even when the panel is half height.
    private var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    private var findBarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }

    private func row(_ segment: Segment) -> some View {
        let isCurrent = !matches.isEmpty && matches[min(matchIndex, matches.count - 1)] == segment.id
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Format.time(segment.time))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(Highlight.text(segment.text, query: trimmedQuery))
                .font(captionFont.font(size: 19))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isCurrent ? Theme.sheetCard : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Moves to the previous (-1) or next (+1) match, wrapping around.
    private func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard !matches.isEmpty else { return }
        withAnimation { proxy.scrollTo(matches[min(matchIndex, matches.count - 1)], anchor: .center) }
    }
}

enum Highlight {
    /// The text with every occurrence of `query` highlighted.
    static func text(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let range = result[searchStart...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].backgroundColor = Color.yellow.opacity(0.45)
            searchStart = range.upperBound
        }
        return result
    }

    /// A short excerpt around the first match, for search results.
    static func snippet(_ text: String, query: String, radius: Int = 70) -> String {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(radius * 2))
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }
}
