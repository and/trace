#if DEBUG
import Foundation

/// Synthetic data for screenshots and previews. DEBUG-only and reached solely
/// via the `-sample-data` launch argument, so it can never stand in for real
/// readings in a shipped build.
///
/// It bypasses HealthKit rather than writing to it: seeding the real store
/// would need write access to heart rate — which this app has no business
/// holding — and would raise a permission sheet that blocks automation.
enum SampleData {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-sample-data")
    }

    /// A day shaped like real wrist data: overnight dip, waking rise, daytime
    /// variation with two active spikes, evening settle.
    static func heartRate(on day: Date, calendar: Calendar = .current) -> [HRSample] {
        let start = calendar.startOfDay(for: day)
        var generator = SeededGenerator(seed: UInt64(start.timeIntervalSince1970))
        var out: [HRSample] = []

        // ~2.6 minute spacing, matching the real background sampling rate.
        for step in stride(from: 0.0, to: 24.0, by: 2.6 / 60.0) {
            var bpm: Double
            switch step {
            case ..<6.5:  bpm = 56 + 4 * sin(step / 2)
            case ..<8:    bpm = 58 + (step - 6.5) * 14
            case ..<21:   bpm = 78 + 7 * sin((step - 8) / 2.4)
            default:      bpm = 72 - (step - 21) * 4
            }
            if step > 10.2 && step < 10.8 { bpm += 34 }   // a walk
            if step > 17.6 && step < 18.1 { bpm += 46 }   // something brisker

            bpm += generator.nextGaussian() * 2.8
            out.append(HRSample(date: start.addingTimeInterval(step * 3600),
                                bpm: min(138, max(50, bpm.rounded()))))
        }
        return out
    }

    /// Sixty days of HRV and resting heart rate, drifting the way a real
    /// baseline does rather than sitting flat.
    static func days(calendar: Calendar = .current) -> [DayMetrics] {
        let today = calendar.startOfDay(for: .now)
        var generator = SeededGenerator(seed: 42)
        var hrv = 42.0
        var rhr = 62.0
        var out: [DayMetrics] = []

        for offset in stride(from: -59, through: 0, by: 1) {
            hrv = max(22, min(68, hrv + generator.nextGaussian() * 3.0))
            rhr = max(52, min(78, rhr + generator.nextGaussian() * 1.4))
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            out.append(DayMetrics(date: date,
                                  hrv: (hrv * 10).rounded() / 10,
                                  restingHR: rhr.rounded(),
                                  stress: nil))
        }
        return StressScore.annotate(out)
    }

    /// A typical-heart-rate-per-hour curve matching the synthetic day.
    static func hourlyBaseline() -> [Int: Double] {
        var out: [Int: Double] = [:]
        for hour in 0..<24 {
            let step = Double(hour)
            switch step {
            case ..<6.5:  out[hour] = 57 + 4 * sin(step / 2)
            case ..<8:    out[hour] = 58 + (step - 6.5) * 14
            case ..<21:   out[hour] = 77 + 7 * sin((step - 8) / 2.4)
            default:      out[hour] = 72 - (step - 21) * 4
            }
        }
        return out
    }

    /// Activities for today, positioned to sit over the interesting parts of
    /// the synthetic trace.
    static func activities(calendar: Calendar = .current) -> [(String, Date, Date)] {
        let start = calendar.startOfDay(for: .now)
        func at(_ hour: Double) -> Date { start.addingTimeInterval(hour * 3600) }
        return [
            ("Deep work", at(9.0), at(11.5)),
            ("Meeting", at(13.0), at(14.0)),
            ("Study", at(15.25), at(17.5)),
        ]
    }
}

/// A tiny deterministic generator, so screenshots are reproducible rather than
/// different on every run.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    private mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    private mutating func nextUnit() -> Double {
        Double(next() % 1_000_000) / 1_000_000.0
    }

    /// Box-Muller, so the noise looks like measurement noise.
    mutating func nextGaussian() -> Double {
        let u1 = max(nextUnit(), 1e-9)
        let u2 = nextUnit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
#endif
