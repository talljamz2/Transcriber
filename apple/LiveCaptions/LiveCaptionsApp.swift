import SwiftUI
import SwiftData

@main
struct LiveCaptionsApp: App {
    private let container: ModelContainer
    @State private var controller: CaptionController

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: CaptionSession.self, DaySummary.self)
        } catch {
            fatalError("Couldn't open the transcript store: \(error)")
        }
        self.container = container
        _controller = State(initialValue: CaptionController(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}

struct ContentView: View {
    @Environment(CaptionController.self) private var controller
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system

    var body: some View {
        TabView {
            Tab("Live", systemImage: "captions.bubble") {
                LiveView()
            }
            Tab("Saved", systemImage: "tray.full") {
                NavigationStack { HistoryView() }
            }
            Tab("Settings", systemImage: "gear") {
                NavigationStack { SettingsView() }
            }
        }
        .groupBoxStyle(.card)
        .preferredColorScheme(appearance.colorScheme)
        .task { controller.resumePendingWork() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await controller.refreshReminder() } }
        }
    }
}
