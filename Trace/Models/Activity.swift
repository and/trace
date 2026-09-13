import Foundation
import SwiftData

@Model
final class Activity {
    var label: String
    var start: Date
    var end: Date?
    var note: String

    /// The mindful-session sample this activity wrote to HealthKit, if any.
    /// Kept so an edit can replace it and a delete can remove it, rather than
    /// leaving orphans in the user's health record.
    var healthSampleID: UUID?

    init(label: String, start: Date = .now, end: Date? = nil, note: String = "") {
        self.label = label
        self.start = start
        self.end = end
        self.note = note
        self.healthSampleID = nil
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

    /// Ordering for the home screen: what you use most comes first, so the
    /// labels you actually reach for stop drifting behind defaults you never
    /// touch. Ties go to whatever you used most recently, then to the built-in
    /// order so an untouched row stays stable rather than reshuffling.
    static func ordered(usage: [(label: String, start: Date)], defaults: [String] = all) -> [String] {
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]
        for entry in usage {
            counts[entry.label, default: 0] += 1
            lastUsed[entry.label] = max(lastUsed[entry.label] ?? entry.start, entry.start)
        }

        let candidates = Set(defaults).union(counts.keys)
        return candidates.sorted { lhs, rhs in
            let lhsCount = counts[lhs] ?? 0
            let rhsCount = counts[rhs] ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }

            if let lhsDate = lastUsed[lhs], let rhsDate = lastUsed[rhs], lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if (lastUsed[lhs] == nil) != (lastUsed[rhs] == nil) { return lastUsed[lhs] != nil }

            let lhsIndex = defaults.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = defaults.firstIndex(of: rhs) ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs < rhs
        }
    }
}
