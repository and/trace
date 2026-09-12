import Foundation

/// One day's health summary plus the derived stress score.
struct DayMetrics: Identifiable, Hashable {
    let date: Date
    var hrv: Double?          // SDNN, ms
    var restingHR: Double?    // bpm
    var stress: Double?       // 0-100, higher = more strain

    var id: Date { date }
}

/// Apple Health has no "stress" type. This derives one from the two signals
/// that actually track autonomic load: HRV (down = more strain) and resting
/// heart rate (up = more strain).
///
/// Each is z-scored against the user's OWN history rather than population
/// norms, because absolute HRV varies enormously between people and only the
/// deviation from your own baseline is meaningful. The two z-scores are
/// averaged, then mapped onto 0-100 with 50 as "a typical day for you".
enum StressScore {

    static func annotate(_ days: [DayMetrics]) -> [DayMetrics] {
        let hrvStats = stats(days.compactMap(\.hrv))
        let rhrStats = stats(days.compactMap(\.restingHR))

        return days.map { day in
            var day = day
            var parts: [Double] = []
            // HRV is inverted: lower HRV means more strain.
            if let hrv = day.hrv, let z = zScore(hrv, hrvStats) { parts.append(-z) }
            if let rhr = day.restingHR, let z = zScore(rhr, rhrStats) { parts.append(z) }

            if parts.isEmpty {
                day.stress = nil
            } else {
                let mean = parts.reduce(0, +) / Double(parts.count)
                // 1 SD of combined strain moves the score 20 points.
                day.stress = min(100, max(0, 50 + mean * 20))
            }
            return day
        }
    }

    private static func stats(_ values: [Double]) -> (mean: Double, sd: Double)? {
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        let sd = sqrt(variance)
        return sd > 0 ? (mean, sd) : nil
    }

    private static func zScore(_ value: Double, _ stats: (mean: Double, sd: Double)?) -> Double? {
        guard let stats else { return nil }
        return (value - stats.mean) / stats.sd
    }
}

/// One heart-rate reading, for the intraday chart.
struct HRSample: Identifiable, Hashable {
    let date: Date
    let bpm: Double
    var id: Date { date }
}
