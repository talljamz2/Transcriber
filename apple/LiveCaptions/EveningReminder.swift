import Foundation
import SwiftData
import UserNotifications

/// One evening notification, scheduled only when there's something to read or review.
@MainActor
enum EveningReminder {
    private static let identifier = "evening-reminder"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.eveningReminder) as? Bool ?? true
    }

    static var minutesAfterMidnight: Int {
        UserDefaults.standard.object(forKey: SettingsKey.reminderMinutes) as? Int ?? 20 * 60
    }

    static func requestPermissionIfNeeded() async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Replaces any pending reminder with one that reflects the current sessions.
    static func update(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let sessions = (try? context.fetch(FetchDescriptor<CaptionSession>())) ?? []
        let toReview = sessions.filter(\.needsReview).count
        let today = Calendar.current.startOfDay(for: .now)
        let todays = sessions.filter { $0.day == today && !($0.category?.isLowValue ?? false) }

        let calendar = Calendar.current
        var fire = calendar.dateComponents([.year, .month, .day], from: .now)
        fire.hour = minutesAfterMidnight / 60
        fire.minute = minutesAfterMidnight % 60
        guard let todayAtTime = calendar.date(from: fire) else { return }

        var parts: [String] = []
        if todayAtTime > .now {
            if !todays.isEmpty {
                parts.append("Today: \(DayStats(todays)). Your daily summary is ready.")
            }
        } else {
            // Too late for today; remind tomorrow evening only if something still needs review.
            guard toReview > 0, let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayAtTime) else { return }
            fire = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrow)
        }
        if toReview > 0 {
            parts.append(toReview == 1 ? "1 TV or media session to review." : "\(toReview) TV or media sessions to review.")
        }
        guard !parts.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Live Captions"
        content.body = parts.joined(separator: " ")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
