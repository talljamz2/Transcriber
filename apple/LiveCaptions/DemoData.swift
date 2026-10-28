#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Sample sessions for screenshots. Launch with `-demo YES -screen live|saved|day|session|settings`.
/// Debug builds only; the data lives in memory and is never saved.
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "demo") }
    /// Which screen to open in demo mode.
    static var screen: String? { isEnabled ? UserDefaults.standard.string(forKey: "screen") : nil }
    /// A search to show in demo mode.
    static var query: String? { isEnabled ? UserDefaults.standard.string(forKey: "demoQuery") : nil }

    struct Seeded {
        let today: Date
        let meeting: CaptionSession
        let live: CaptionSession
        let liveVolatile = "If you have any questions you can call the"
    }

    @MainActor
    static func load(into context: ModelContext, controller: CaptionController, tab: inout Int, path: inout NavigationPath) {
        let seeded = seed(into: context, controller: controller)
        switch screen ?? "live" {
        case "saved", "search": tab = 1
        case "day": tab = 1; path.append(SavedRoute.day(seeded.today))
        case "session": tab = 1; path.append(seeded.meeting)
        case "settings": tab = 2
        default: controller.showDemoLive(seeded.live, volatile: seeded.liveVolatile)
        }
    }

    /// Inserts the sample sessions. Also used by the Xcode previews.
    @MainActor
    static func seed(into context: ModelContext, controller: CaptionController) -> Seeded {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        func at(_ day: Date, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }

        let meeting = session(
            "Quarterly budget review", at(today, 10, 2), minutes: 42, .meeting,
            oneLiner: "Team meeting about the Q3 budget and the offsite",
            lines: [
                "Okay, let's get started. The main thing today is the Q3 budget.",
                "Travel is about twelve percent over, mostly from the conference in Denver.",
                "I'll send the revised budget to Sarah by Friday.",
                "Tom, can you book the venue for the offsite before the end of the month?",
                "Sure, I'll look at the two places we talked about.",
                "We still need someone to follow up with finance about the travel costs.",
            ],
            overview: "The team reviewed the Q3 budget. Travel is running about 12% over, mainly because of the Denver conference. They agreed to trim next quarter's travel and plan the offsite.",
            keyPoints: ["Travel is 12% over budget, mostly the Denver conference.", "Next quarter's travel will be trimmed to make up the difference.", "Two venues are shortlisted for the offsite."],
            decisions: ["Keep the offsite in November.", "Pause non-essential travel until January."],
            actions: [
                ActionItem(task: "Send the revised budget to Sarah", owner: .me, due: "by Friday", dueDate: cal.date(byAdding: .day, value: 2, to: today), quote: "I'll send the revised budget to Sarah by Friday."),
                ActionItem(task: "Book the venue for the offsite", owner: .other, person: "Tom", due: "before the end of the month", quote: "Tom, can you book the venue for the offsite"),
                ActionItem(task: "Follow up with finance about travel costs", owner: .unclear, quote: "We still need someone to follow up with finance"),
            ],
            topics: ["budget", "travel", "offsite"]
        )
        let note = session(
            "Remember to call the plumber", at(today, 12, 40), minutes: 1, .voiceNote,
            oneLiner: "Note about the kitchen leak and groceries",
            lines: ["Remember to call the plumber about the kitchen leak tomorrow morning.", "Also pick up coffee and oat milk on the way home."],
            overview: "A reminder to call the plumber about the kitchen leak and to pick up groceries.",
            keyPoints: ["The kitchen tap is still leaking."],
            decisions: [],
            actions: [
                ActionItem(task: "Call the plumber about the kitchen leak", owner: .me, due: "tomorrow morning", dueDate: cal.date(byAdding: .day, value: 1, to: today), quote: "call the plumber about the kitchen leak tomorrow morning"),
                ActionItem(task: "Buy coffee and oat milk", owner: .me, due: "on the way home", quote: "pick up coffee and oat milk"),
            ],
            topics: ["home", "errands"]
        )
        let lecture = session(
            "Hearing technology talk", at(today, 15, 0), minutes: 55, .lecture,
            oneLiner: "Library talk on new hearing technology",
            lines: ["Tonight I want to talk about how hearing aids have changed in the last five years."],
            overview: "A talk at the library about recent hearing technology, including on-device captions and Bluetooth hearing aids.",
            keyPoints: ["Modern hearing aids stream directly from phones.", "Live captions now run on the device without internet."],
            decisions: [], actions: [], topics: ["hearing", "technology"]
        )
        let hockey = session(
            "And he shoots, he scores", at(today, 19, 30), minutes: 64, .media,
            oneLiner: "Hockey game commentary",
            lines: ["And he shoots, he scores! What a goal in the second period."],
            overview: "", keyPoints: [], decisions: [], actions: [], topics: []
        )
        let dinner = session(
            "Dinner with Alex", at(yesterday, 19, 15), minutes: 38, .conversation,
            oneLiner: "Dinner conversation about Alex's new job and a ski trip",
            lines: ["So how's the new job going?", "Let's plan the ski trip for February."],
            overview: "Catching up with Alex about the new job and planning a ski trip for February.",
            keyPoints: ["Alex started at the design studio last month.", "February works for the ski trip."],
            decisions: ["Go skiing the second weekend of February."],
            actions: [ActionItem(task: "Look up cabins for the ski trip", owner: .unclear, due: "next week", quote: "I'll look up some cabins next week")],
            topics: ["friends", "travel"]
        )
        let news = session(
            "Good evening, here are tonight's headlines", at(yesterday, 18, 0), minutes: 30, .media,
            oneLiner: "Evening news broadcast",
            lines: ["Good evening, here are tonight's headlines."],
            overview: "", keyPoints: [], decisions: [], actions: [], topics: []
        )
        for s in [meeting, note, lecture, hockey, dinner, news] { context.insert(s) }

        let day = DaySummary(day: today)
        day.brief = "A busy day: you reviewed the Q3 budget with the team, left yourself a reminder about the kitchen leak, and went to a talk on hearing technology. You have three things to do, the most urgent being the revised budget for Sarah by Friday."
        day.themes = ["Keeping travel costs down", "Planning the November offsite", "Home repairs"]
        day.sourceFingerprint = controller.fingerprint(controller.usefulSessions(on: today))
        context.insert(day)

        // What's being said "right now" on the Live tab.
        let live = CaptionSession(localeIdentifier: "en-US")
        let now = Date.now
        live.segments = [
            Segment(time: now.addingTimeInterval(-300), text: "Good morning. Have a seat, the doctor will be with you shortly."),
            Segment(time: now.addingTimeInterval(-240), text: "Are you still taking the blood pressure medication we started in June?"),
            Segment(time: now.addingTimeInterval(-200), text: "Any dizziness or headaches since then?"),
            Segment(time: now.addingTimeInterval(-160), text: "Okay, and how has your sleep been?"),
            Segment(time: now.addingTimeInterval(-120), text: "Let's take your blood pressure again before we finish."),
            Segment(time: now.addingTimeInterval(-40), text: "Thanks for coming in today. I've had a look at your results from last week."),
            Segment(time: now.addingTimeInterval(-28), text: "Overall things look good. Your blood pressure is down since the last visit."),
            Segment(time: now.addingTimeInterval(-9), text: "I'd like you to keep taking the medication twice a day with food,"),
            Segment(time: now.addingTimeInterval(-1), text: "and we'll check again in about six weeks."),
        ]

        return Seeded(today: today, meeting: meeting, live: live)
    }

    @MainActor
    private static func session(
        _ title: String, _ start: Date, minutes: Double, _ category: SessionCategory,
        oneLiner: String, lines: [String], overview: String, keyPoints: [String], decisions: [String],
        actions: [ActionItem], topics: [String]
    ) -> CaptionSession {
        let s = CaptionSession(localeIdentifier: "en-US")
        s.title = title
        s.hasSmartTitle = true
        s.startedAt = start
        s.endedAt = start.addingTimeInterval(minutes * 60)
        let step = minutes * 60 / Double(max(lines.count, 1))
        s.segments = lines.enumerated().map { i, line in Segment(time: start.addingTimeInterval(Double(i) * step), text: line) }
        s.category = category
        s.oneLiner = oneLiner
        s.overview = overview
        if !overview.isEmpty {
            var md = "## Overview\n\(overview)\n"
            if !keyPoints.isEmpty { md += "\n## Key points\n" + keyPoints.map { "- \($0)" }.joined(separator: "\n") + "\n" }
            if !decisions.isEmpty { md += "\n## Decisions\n" + decisions.map { "- \($0)" }.joined(separator: "\n") + "\n" }
            s.summary = md
            s.summarySource = "apple"
        }
        s.actions = actions
        s.topics = topics
        s.processing = .done
        return s
    }
}
#endif
