import Testing
import Foundation
@testable import Trace

/// Per-activity heart rate. This is what replaced the daily strain score, and
/// the property that matters is the one strain never had: two activities on
/// the same day must be able to differ.
struct ActivityLoadTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private func samples(_ pairs: [(String, Double)]) -> [HRSample] {
        pairs.map { HRSample(date: date($0.0), bpm: $0.1) }
    }

    private let flatBaseline = Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, 70.0) })

    @Test func averagesOnlyTheReadingsInsideTheActivity() {
        let load = LoadCalculator.load(
            label: "Study",
            start: date("2026-09-12 10:00"),
            end: date("2026-09-12 11:00"),
            samples: samples([
                ("2026-09-12 09:30", 200),   // before — must be ignored
                ("2026-09-12 10:15", 80),
                ("2026-09-12 10:45", 90),
                ("2026-09-12 11:30", 200),   // after — must be ignored
            ]),
            hourly: flatBaseline,
            calendar: cal
        )
        #expect(load?.sampleCount == 2)
        #expect(load?.meanBPM == 85)
        #expect(load?.peakBPM == 90)
    }

    /// The whole point of the change: same day, different numbers.
    @Test func twoActivitiesOnTheSameDayCanDiffer() {
        let all = samples([
            ("2026-09-12 10:15", 72), ("2026-09-12 10:45", 74),
            ("2026-09-12 15:15", 96), ("2026-09-12 15:45", 104),
        ])
        let morning = LoadCalculator.load(label: "Reading",
                                          start: date("2026-09-12 10:00"),
                                          end: date("2026-09-12 11:00"),
                                          samples: all, hourly: flatBaseline, calendar: cal)
        let afternoon = LoadCalculator.load(label: "Study",
                                            start: date("2026-09-12 15:00"),
                                            end: date("2026-09-12 16:00"),
                                            samples: all, hourly: flatBaseline, calendar: cal)
        #expect(morning?.meanBPM == 73)
        #expect(afternoon?.meanBPM == 100)
        #expect(morning?.meanBPM != afternoon?.meanBPM)
    }

    @Test func deltaIsMeasuredAgainstTheHourlyBaseline() {
        let load = LoadCalculator.load(
            label: "Meeting",
            start: date("2026-09-12 14:00"),
            end: date("2026-09-12 15:00"),
            samples: samples([("2026-09-12 14:30", 88)]),
            hourly: flatBaseline, calendar: cal
        )
        #expect(load?.delta == 18)
    }

    @Test func returnsNilWhenNoReadingFallsInside() {
        let load = LoadCalculator.load(
            label: "Study",
            start: date("2026-09-12 10:00"),
            end: date("2026-09-12 11:00"),
            samples: samples([("2026-09-12 12:00", 80)]),
            hourly: flatBaseline, calendar: cal
        )
        #expect(load == nil)
    }

    @Test func aThinlySampledActivityIsMarkedUnreliable() {
        let thin = LoadCalculator.load(
            label: "Study", start: date("2026-09-12 10:00"), end: date("2026-09-12 10:10"),
            samples: samples([("2026-09-12 10:05", 80)]), hourly: flatBaseline, calendar: cal)
        #expect(thin?.isReliable == false)

        let dense = LoadCalculator.load(
            label: "Study", start: date("2026-09-12 10:00"), end: date("2026-09-12 11:00"),
            samples: samples((0..<6).map { ("2026-09-12 10:0\($0)", 80.0) }),
            hourly: flatBaseline, calendar: cal)
        #expect(dense?.isReliable == true)
    }

    @Test func noBaselineMeansNoDelta() {
        let load = LoadCalculator.load(
            label: "Study", start: date("2026-09-12 10:00"), end: date("2026-09-12 11:00"),
            samples: samples([("2026-09-12 10:30", 80)]), hourly: [:], calendar: cal)
        #expect(load?.baselineBPM == nil)
        #expect(load?.delta == nil)
    }

    // MARK: - Baseline construction

    @Test func hourlyBaselineTakesTheMedianPerHour() {
        let entries: [(date: Date, bpm: Double)] = [
            (date("2026-09-01 10:00"), 70), (date("2026-09-02 10:00"), 72),
            (date("2026-09-03 10:00"), 74), (date("2026-09-04 10:00"), 76),
            (date("2026-09-05 10:00"), 200),   // an outlier a mean would swallow
        ]
        let baseline = LoadCalculator.hourlyBaseline(hourlyAverages: entries, calendar: cal)
        #expect(baseline[10] == 74)
    }

    @Test func hoursWithTooLittleHistoryAreOmitted() {
        let entries: [(date: Date, bpm: Double)] = [
            (date("2026-09-01 03:00"), 55), (date("2026-09-02 03:00"), 57),
        ]
        #expect(LoadCalculator.hourlyBaseline(hourlyAverages: entries, calendar: cal)[3] == nil)
    }

    /// An activity spanning two hours is compared against both, weighted by how
    /// much of it fell in each.
    @Test func baselineAcrossHoursIsWeightedByTimeSpent() {
        let hourly = [14: 60.0, 15: 80.0]
        let value = LoadCalculator.baseline(
            forSpanFrom: date("2026-09-12 14:45"),
            to: date("2026-09-12 15:45"),
            hourly: hourly, calendar: cal
        )
        // 15 minutes at 60, 45 at 80.
        #expect(value == 75)
    }

    @Test func baselineIsNilForAnInvertedSpan() {
        #expect(LoadCalculator.baseline(forSpanFrom: date("2026-09-12 15:00"),
                                        to: date("2026-09-12 14:00"),
                                        hourly: [14: 60, 15: 80], calendar: cal) == nil)
    }
}
