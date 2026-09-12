import Foundation
import SwiftData

@Model
final class Activity {
    var label: String
    var start: Date
    var end: Date?
    var note: String

    init(label: String, start: Date = .now, end: Date? = nil, note: String = "") {
        self.label = label
        self.start = start
        self.end = end
        self.note = note
    }

    var isRunning: Bool { end == nil }

    var duration: TimeInterval {
        (end ?? .now).timeIntervalSince(start)
    }

    /// Days this activity touches, so a session that crosses midnight is
    /// counted against both dates when overlaying onto daily metrics.
    func days(in calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end ?? .now)
        while day <= last {
            out.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }
}

/// The labels offered as quick picks. Free text is still allowed.
enum QuickLabel {
    static let all = ["Study", "Deep work", "Meeting", "Reading", "Commute", "Chores"]
}
