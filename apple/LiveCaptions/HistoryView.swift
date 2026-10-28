import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum SavedRoute: Hashable {
    case day(Date)
    case tidyUp
    /// A session opened from search, with its transcript search ready.
    case match(CaptionSession, String)
}

struct HistoryView: View {
    @Environment(CaptionController.self) private var controller
    @Query(sort: \CaptionSession.startedAt, order: .reverse) private var sessions: [CaptionSession]
    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var days: [(day: Date, sessions: [CaptionSession])] {
        Dictionary(grouping: sessions, by: \.day)
            .map { (day: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    private var reviewCount: Int { sessions.filter(\.needsReview).count }

    var body: some View {
        Group {
            if !trimmedQuery.isEmpty {
                SearchResultsView(sessions: sessions, query: trimmedQuery)
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No saved sessions",
                    systemImage: "tray",
                    description: Text("Everything you caption is saved here automatically, sorted by day.")
                )
            } else {
                List {
                    if reviewCount > 0 {
                        Section {
                            NavigationLink(value: SavedRoute.tidyUp) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Tidy up").font(.headline)
                                        Text(reviewCount == 1 ? "1 session looks like TV or media" : "\(reviewCount) sessions look like TV or media")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "sparkles").foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    ForEach(days, id: \.day) { group in
                        Section(Format.day(group.day)) {
                            let useful = group.sessions.filter { !($0.category?.isLowValue ?? false) }
                            if !useful.isEmpty {
                                NavigationLink(value: SavedRoute.day(group.day)) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Daily summary").font(.headline)
                                            Text(DayStats(useful).description.capitalizedFirst)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "sun.max").foregroundStyle(.yellow)
                                    }
                                }
                            }
                            ForEach(group.sessions) { session in
                                NavigationLink(value: session) {
                                    SessionRow(session: session)
                                }
                            }
                            .onDelete { offsets in
                                controller.delete(offsets.map { group.sessions[$0] })
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved")
        .searchable(text: $query, prompt: "Search all sessions")
        #if DEBUG
        .onAppear { if let demo = DemoData.query, query.isEmpty { query = demo } }
        #endif
        .navigationDestination(for: CaptionSession.self) { session in
            SessionDetailView(session: session)
        }
        .navigationDestination(for: SavedRoute.self) { route in
            switch route {
            case .day(let day): DayView(day: day)
            case .tidyUp: TidyUpView()
            case .match(let session, let query): SessionDetailView(session: session, findQuery: query)
            }
        }
    }
}

struct SessionRow: View {
    let session: CaptionSession
    @Environment(CaptionController.self) private var controller

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.category?.symbol ?? "text.bubble")
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle).font(.headline).lineLimit(2)
                if !session.oneLiner.isEmpty {
                    Text(session.oneLiner).font(.subheadline).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(meta).foregroundStyle(.secondary)
                    if controller.isLive(session) {
                        Text("Recording").foregroundStyle(.red)
                    } else if controller.isQueued(session) {
                        ProgressView().controlSize(.mini)
                        Text("Sorting…").foregroundStyle(.secondary)
                    } else if session.needsReview {
                        Text("Review")
                            .padding(.horizontal, 6)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var meta: String {
        var parts = [Format.time(session.startedAt), Format.duration(session.duration)]
        if let category = session.category { parts.append(category.name) }
        return parts.joined(separator: " · ")
    }
}

struct SessionDetailView: View {
    @Bindable var session: CaptionSession
    /// Opens the transcript search with this text, when arriving from search results.
    var findQuery = ""
    @State private var showFind = false
    @Environment(\.dismiss) private var dismiss
    @Environment(CaptionController.self) private var controller
    @State private var confirmDelete = false
    @State private var copied = false
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .newYork

    private var isLive: Bool { controller.isLive(session) }
    private var isWorking: Bool { controller.isQueued(session) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if session.needsReview { reviewBanner }

                if isWorking {
                    HStack {
                        ProgressView()
                        Text("Sorting and summarizing…").foregroundStyle(.secondary)
                    }
                }

                if !session.actions.isEmpty {
                    SectionTitle("Actions")
                    ActionsList(entries: session.actions.map { ActionEntry(session: session, action: $0) }, showSource: false)
                }

                SectionTitle("Summary")
                GroupBox { summaryContent }

                if !session.topics.isEmpty {
                    Text(session.topics.map { "#\($0)" }.joined(separator: "  "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                buttons

                SectionTitle("Full transcript")
                GroupBox {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.segments) { segment in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Format.time(segment.time))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(segment.text)
                            }
                        }
                    }
                    .font(captionFont.font(size: 17))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .navigationTitle(session.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button {
                showFind = true
            } label: {
                Label("Find in transcript", systemImage: "text.magnifyingglass")
            }
        }
        .sheet(isPresented: $showFind) {
            TranscriptSearchView(session: session, initialQuery: findQuery)
                .presentationDragIndicator(.visible)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                #endif
        }
        .onAppear { if !findQuery.isEmpty { showFind = true } }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                controller.delete([session])
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $session.title)
                .font(captionFont.font(size: 28, weight: .semibold))
                .textFieldStyle(.plain)
            Text("\(Format.dateTime(session.startedAt)) · \(Format.duration(session.duration)) · \(session.wordCount) words")
                .foregroundStyle(.secondary)
            Menu {
                ForEach(SessionCategory.allCases) { category in
                    Button {
                        controller.setCategory(category, for: session)
                    } label: {
                        Label(category.name, systemImage: category.symbol)
                    }
                }
            } label: {
                Label(session.category?.name ?? "Not sorted yet", systemImage: session.category?.symbol ?? "questionmark.circle")
            }
            .fixedSize()
            .disabled(isLive)
            if !session.oneLiner.isEmpty {
                Text(session.oneLiner).foregroundStyle(.secondary)
            }
        }
    }

    private var reviewBanner: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("This looks like TV or media.", systemImage: "tv")
                    .font(.headline)
                Text("Keep it, or delete it if you don't need it.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Keep") { controller.keep(session) }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        if isWorking {
            Text("The summary will appear here in a moment.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if session.summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.category?.isLowValue == true
                     ? "TV & media sessions aren't summarized automatically."
                     : "No summary yet.")
                    .foregroundStyle(.secondary)
                Button("Summarize") { controller.summarize(session) }
                    .buttonStyle(.bordered)
                    .disabled(isLive)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            SummaryText(markdown: session.summary, font: captionFont)
            if session.summarySource == "apple" {
                Text("Written on this device by Apple Intelligence.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private var buttons: some View {
        HStack {
            Button("Summarize again") { controller.summarize(session) }
                .disabled(isWorking || isLive || session.summary.isEmpty)

            Button(copied ? "Copied" : "Copy") {
                copy(session.exportText())
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }

            ShareLink(item: session.exportText(), subject: Text(session.displayTitle)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Spacer()

            Button("Delete", role: .destructive) { confirmDelete = true }
                .disabled(isLive)
        }
        .buttonStyle(.bordered)
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Renders the small Markdown subset the summaries use: `##` headings, `-` bullets, and **bold**.
struct SummaryText: View {
    let markdown: String
    var font: CaptionFont = .newYork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, rawLine in
                line(rawLine.trimmingCharacters(in: .whitespaces))
            }
        }
        .font(font.font(size: 17))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func line(_ line: String) -> some View {
        if line.hasPrefix("#") {
            Text(inline(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                .font(font.font(size: 18, weight: .semibold))
                .padding(.top, 6)
        } else if let first = line.first, "-*•".contains(first), line.dropFirst().first == " " {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(inline(String(line.dropFirst(2))))
            }
        } else if !line.isEmpty {
            Text(inline(line))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// A quiet section heading, like those in Apple's own apps.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}
