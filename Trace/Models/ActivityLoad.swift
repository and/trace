import Foundation

/// What your heart actually did during one logged activity.
///
/// Unlike the daily strain score this replaces, every number here comes from
/// readings taken *while the activity was happening* — so it can separate two
/// things done on the same day, which a per-day score never could.
struct ActivityLoad: Equatable {
    let label: String
    let start: Date
    let end: Date
    let sampleCount: Int
    let meanBPM: Double
    let peakBPM: Double

    /// Your typical heart rate for the hours this activity covered. Nil when
    /// there is not enough history for those hours to compare against.
    let baselineBPM: Double?

    /// How far above (or below) your usual this activity ran, in bpm — a real
    /// unit, deliberately not a 0-100 score that means nothing on its own.
    var delta: Double? {
        baselineBPM.map { meanBPM - $0 }
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Heart rate outside a workout is sampled every couple of minutes, so a
    /// short activity can rest on two or three readings. Below this the mean
    /// is noise wearing a number.
    var isReliable: Bool { sampleCount >= 5 }
}

enum LoadCalculator {

    /// Typical heart rate per hour of day, as a median over whatever history is
    /// available. Median rather than mean: a single workout in an hour slot
    /// would drag a mean up and make every later session look calm by
    /// comparison.
    static func hourlyBaseline(
        hourlyAverages: [(date: Date, bpm: Double)],
        calendar: Calendar = .current,
        minimumDays: Int = 5
    ) -> [Int: Double] {
        var byHour: [Int: [Double]] = [:]
        for entry in hourlyAverages {
            byHour[calendar.component(.hour, from: entry.date), default: []].append(entry.bpm)
        }
        return byHour.compactMapValues { values in
            guard values.count >= minimumDays else { return nil }
            return median(values)
        }
    }

    /// The baseline for a span, weighted by how much of it falls in each hour —
    /// an activity from 14:45 to 16:15 is mostly hour 15, and should be
    /// compared accordingly.
    static func baseline(
        forSpanFrom start: Date,
        to end: Date,
        hourly: [Int: Double],
        calendar: Calendar = .current
    ) -> Double? {
        guard end > start else { return nil }

        var weighted = 0.0
        var total = 0.0
        var cursor = start

        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let nextBoundary = calendar.nextDate(
                after: cursor,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? end
            let sliceEnd = min(nextBoundary, end)
            let seconds = sliceEnd.timeIntervalSince(cursor)
            guard seconds > 0 else { break }

            if let value = hourly[hour] {
                weighted += value * seconds
                total += seconds
            }
            cursor = sliceEnd
        }

        guard total > 0 else { return nil }
        return weighted / total
    }

    /// Builds the summary for one activity. Returns nil when no reading falls
    /// inside it at all — a blank row says less than no row.
    static func load(
        label: String,
        start: Date,
        end: Date,
        samples: [HRSample],
        hourly: [Int: Double],
        calendar: Calendar = .current
    ) -> ActivityLoad? {
        let inside = samples.filter { $0.date >= start && $0.date <= end }
        guard !inside.isEmpty else { return nil }

        let values = inside.map(\.bpm)
        return ActivityLoad(
            label: label,
            start: start,
            end: end,
            sampleCount: values.count,
            meanBPM: values.reduce(0, +) / Double(values.count),
            peakBPM: values.max() ?? 0,
            baselineBPM: baseline(forSpanFrom: start, to: end, hourly: hourly, calendar: calendar)
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
