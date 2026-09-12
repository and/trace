import Foundation

/// One activity clipped to a single day, ready to draw as a chart band.
struct BandSpan: Equatable {
    let label: String
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Clipping an activity to a day. A session that crosses midnight must appear
/// on both days, trimmed to each — and one that misses the day entirely must
/// not appear at all. Pure so it can be tested without a view or a store.
enum BandLayout {

    /// Returns the portion of `start..<end` that falls inside the given day, or
    /// nil when there is no overlap. `end` may be nil for a running activity,
    /// in which case `now` bounds it.
    static func clip(
        label: String,
        start: Date,
        end: Date?,
        toDayStarting dayStart: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BandSpan? {
        let bounds = DayCursor.bounds(of: dayStart, calendar: calendar)
        let effectiveEnd = end ?? now

        let clippedStart = max(start, bounds.lowerBound)
        let clippedEnd = min(effectiveEnd, bounds.upperBound)

        // Strictly greater: a zero-width band is invisible and would only add
        // a stray label to the chart.
        guard clippedEnd > clippedStart else { return nil }
        return BandSpan(label: label, start: clippedStart, end: clippedEnd)
    }
}
