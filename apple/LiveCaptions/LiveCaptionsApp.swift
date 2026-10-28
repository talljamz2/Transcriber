import SwiftUI
import SwiftData

@main
struct LiveCaptionsApp: App {
    private let container: ModelContainer
    @State private var controller: CaptionController

    init() {
        let container: ModelContainer
        do {
            #if DEBUG
            let inMemory = DemoData.isEnabled
            #else
            let inMemory = false
            #endif
            container = try ModelContainer(
                for: CaptionSession.self, DaySummary.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
            )
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
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system
    @State private var tab = 0
    @State private var savedPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            Tab("Live", systemImage: "captions.bubble", value: 0) {
                LiveView()
            }
            Tab("Saved", systemImage: "tray.full", value: 1) {
                NavigationStack(path: $savedPath) { HistoryView() }
            }
            Tab("Settings", systemImage: "gear", value: 2) {
                NavigationStack { SettingsView() }
            }
        }
        .groupBoxStyle(.card)
        .preferredColorScheme(appearance.colorScheme)
        .task {
            #if DEBUG
            if DemoData.isEnabled {
                DemoData.load(into: context, controller: controller, tab: &tab, path: &savedPath)
                return
            }
            #endif
            controller.resumePendingWork()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await controller.refreshReminder() } }
        }
    }
}
