#if DEBUG
import SwiftUI
import SwiftData

/// Sample data for Xcode previews: open any of these files and choose Editor › Canvas
/// (⌥⌘↩) to see the screens without running the app.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: CaptionSession.self, DaySummary.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return container
    }()
    static let controller = CaptionController(context: container.mainContext)
    static let seeded = DemoData.seed(into: container.mainContext, controller: controller)
}

private struct PreviewEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        _ = PreviewData.seeded
        return content
            .modelContainer(PreviewData.container)
            .environment(PreviewData.controller)
            .groupBoxStyle(.card)
    }
}

extension View {
    func previewEnvironment() -> some View { modifier(PreviewEnvironment()) }
}

#Preview("Live") {
    LiveView()
        .previewEnvironment()
        .onAppear {
            PreviewData.controller.showDemoLive(PreviewData.seeded.live, volatile: PreviewData.seeded.liveVolatile)
        }
}

#Preview("Saved") {
    NavigationStack { HistoryView() }
        .previewEnvironment()
}

#Preview("Session") {
    NavigationStack { SessionDetailView(session: PreviewData.seeded.meeting) }
        .previewEnvironment()
}

#Preview("Daily summary") {
    NavigationStack { DayView(day: PreviewData.seeded.today) }
        .previewEnvironment()
}

#Preview("Find in transcript") {
    TranscriptSearchView(session: PreviewData.seeded.live, initialQuery: "medication")
        .previewEnvironment()
}

#Preview("Settings") {
    NavigationStack { SettingsView() }
        .previewEnvironment()
}

#Preview("Whole app") {
    ContentView()
        .previewEnvironment()
}
#endif
