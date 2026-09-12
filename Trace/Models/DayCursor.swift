import Foundation

/// Day-by-day navigation for the intraday chart, kept out of the view so it
/// can be tested. The rule that matters: you can never walk into the future,
/// and stepping is always clamped rather than silently allowed.
enum DayCursor {

    /// The day after `day` has not started yet — i.e. `day` is today or later.
    static func isAtPresent(day: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return true }
        return next > now
    }

    /// Steps the cursor, refusing to move past today. Returns nil when the move
    /// is not allowed, so the caller leaves state untouched.
    static func step(
        from day: Date,
        by days: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard days != 0 else { return nil }
        guard let candidate = calendar.date(byAdding: .day, value: days, to: day) else { return nil }
        let today = calendar.startOfDay(for: now)
        guard candidate <= today else { return nil }
        return calendar.startOfDay(for: candidate)
    }

    /// Bounds of the day, for the chart's x domain.
    static func bounds(of day: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start...end
    }
}
