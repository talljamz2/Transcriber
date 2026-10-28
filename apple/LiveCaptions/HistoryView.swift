import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(CaptionController.self) private var controller
    @Query(sort: \CaptionSession.startedAt, order: .reverse) private var sessions: [CaptionSession]

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No saved transcripts",
                    systemImage: "tray",
                    description: Text("Start a live session and press Stop to save it.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.displayTitle).font(.headline)
                                Text(meta(for: session))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets where !isLive(sessions[index]) {
                            context.delete(sessions[index])
                        }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Saved")
        .navigationDestination(for: CaptionSession.self) { session in
            SessionDetailView(session: session)
        }
    }

    private func isLive(_ session: CaptionSession) -> Bool {
        controller.isRecording && controller.current?.id == session.id
    }

    private func meta(for session: CaptionSession) -> String {
        var parts = [Format.dateTime(session.startedAt), Format.duration(session.duration), "\(session.wordCount) words"]
        if isLive(session) { parts.append("recording now") }
        return parts.joined(separator: " · ")
    }
}

struct SessionDetailView: View {
    @Bindable var session: CaptionSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CaptionController.self) private var controller
    @State private var confirmDelete = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Title", text: $session.title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                Text("\(Format.dateTime(session.startedAt)) · \(Format.duration(session.duration)) · \(session.wordCount) words")
                    .foregroundStyle(.secondary)

                actions

                Text("Summary").font(.title3.bold())
                GroupBox {
                    if controller.isSummarizing {
                        HStack {
                            ProgressView()
                            Text("Writing summary…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if session.summary.isEmpty {
                        Text("No summary yet. Press “Summarize” to create one.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SummaryText(markdown: session.summary)
                        if session.summarySource == "apple" {
                            Text("Summary written on-device by Apple Intelligence.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                }

                Text("Full transcript").font(.title3.bold())
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
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(session.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Delete this transcript?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                context.delete(session)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var actions: some View {
        let isLive = controller.isRecording && controller.current?.id == session.id
        return HStack {
            Button(session.summary.isEmpty ? "Summarize" : "Summarize again") {
                Task { await controller.summarize(session) }
            }
            .disabled(controller.isSummarizing || isLive)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, rawLine in
                line(rawLine.trimmingCharacters(in: .whitespaces))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func line(_ line: String) -> some View {
        if line.hasPrefix("#") {
            Text(inline(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                .font(.headline)
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
