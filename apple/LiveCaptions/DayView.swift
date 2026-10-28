import SwiftUI
import SwiftData

/// The daily summary: a short recap, every action from the day, and each session in one line.
struct DayView: View {
    let day: Date
    @Environment(CaptionController.self) private var controller
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .newYork
    @Query private var sessions: [CaptionSession]
    @Query private var summaries: [DaySummary]

    init(day: Date) {
        self.day = day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        _sessions = Query(
            filter: #Predicate<CaptionSession> { $0.startedAt >= day && $0.startedAt < end },
            sort: \.startedAt
        )
        _summaries = Query(filter: #Predicate<DaySummary> { $0.day == day })
    }

    private var useful: [CaptionSession] {
        sessions.filter { !($0.category?.isLowValue ?? false) && !controller.isLive($0) }
    }

    private var isBuilding: Bool { controller.buildingDays.contains(day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.day(day)).font(captionFont.font(size: 34, weight: .semibold))
                    Text(day.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                    Text(DayStats(useful).description.capitalizedFirst).foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if isBuilding {
                            HStack {
                                ProgressView()
                                Text("Summarizing your day…").foregroundStyle(.secondary)
                            }
                        }
                        if let summary = summaries.first, !summary.brief.isEmpty {
                            Text(summary.brief).font(captionFont.font(size: 17))
                            if !summary.themes.isEmpty {
                                Text("Themes").font(.headline).padding(.top, 4)
                                ForEach(summary.themes, id: \.self) { theme in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("•")
                                        Text(theme)
                                    }
                                    .font(captionFont.font(size: 17))
                                }
                            }
                        } else if !isBuilding {
                            Text("No summary yet.").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Your day in brief", systemImage: "sun.max")
                }

                let entries = useful.flatMap { session in
                    session.actions.map { ActionEntry(session: session, action: $0) }
                }
                if !entries.isEmpty {
                    SectionTitle("Actions")
                    ActionsList(entries: entries)
                }

                SectionTitle("Sessions")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(useful) { session in
                        NavigationLink(value: session) {
                            SessionRow(session: session)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .navigationTitle("Daily summary")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button {
                Task { await controller.buildDaySummary(for: day) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isBuilding)
        }
        .task {
            if controller.isDaySummaryStale(day) {
                await controller.buildDaySummary(for: day)
            }
        }
    }
}
