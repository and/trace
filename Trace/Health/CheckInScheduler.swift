import Foundation
import UserNotifications

/// Occasional "what are you doing right now?" prompts.
///
/// These exist to keep the elevated-heart-rate prompts honest. Labelling only
/// the moments your heart rate was up would mean never observing an activity at
/// a normal rate — so you could say what you do when elevated, but never
/// whether an activity raises your heart rate at all, having nothing to compare
/// against.
enum CheckInScheduler {

    private static let identifierPrefix = "checkin-"

    /// Waking hours only. A prompt at 03:00 collects nothing but annoyance.
    static let hours = [11, 15, 19]

    static func reschedule(labels: [String]) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        )

        guard !labels.isEmpty else { return }

        for hour in hours {
            let content = UNMutableNotificationContent()
            content.title = "What are you doing?"
            content.body = "A quick note keeps your activity data comparable."
            content.categoryIdentifier = PromptID.checkInCategory
            // No start/end: a check-in logs a short window around now, whereas
            // an elevated-HR prompt carries the window the watch flagged.
            content.sound = nil

            var components = DateComponents()
            components.hour = hour
            components.minute = 0

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(hour)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try? await center.add(request)
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        )
    }
}
