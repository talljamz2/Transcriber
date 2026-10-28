import SwiftUI
import SwiftData

/// Sessions that look like TV or media, for the user to delete or keep. Nothing is deleted automatically.
struct TidyUpView: View {
    @Environment(CaptionController.self) private var controller
    @Query(sort: \CaptionSession.startedAt, order: .reverse) private var allSessions: [CaptionSession]
    @State private var confirmDeleteAll = false

    private var flagged: [CaptionSession] { allSessions.filter(\.needsReview) }

    var body: some View {
        Group {
            if flagged.isEmpty {
                ContentUnavailableView(
                    "All tidy",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing to review right now.")
                )
            } else {
                List {
                    Section {
                        ForEach(flagged) { session in
                            NavigationLink(value: session) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.oneLiner.isEmpty ? session.displayTitle : session.oneLiner)
                                        .font(.headline)
                                    Text("\(Format.day(session.day)), \(Format.time(session.startedAt)) · \(Format.duration(session.duration))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { controller.delete([session]) }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Keep") { controller.keep(session) }.tint(.green)
                            }
                        }
                    } footer: {
                        Text("These look like TV, films, sports or other media. Swipe left to delete, or right to keep.")
                    }
                }
                .toolbar {
                    Button("Delete all", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .navigationTitle("Tidy up")
        .confirmationDialog(
            "Delete \(flagged.count) sessions?",
            isPresented: $confirmDeleteAll
        ) {
            Button("Delete all", role: .destructive) { controller.delete(flagged) }
        } message: {
            Text("This can't be undone.")
        }
    }
}
