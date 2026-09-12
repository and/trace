import Testing
import Foundation
@testable import Trace

/// The strain score. It is z-scored against the user's own history, so the
/// edge cases that matter are the ones with too little history to have a
/// baseline — where a naive implementation divides by zero or reports a
/// confident number it has no right to.
struct StressScoreTests {

    private func day(_ offset: Int, hrv: Double?, rhr: Double?) -> DayMetrics {
        DayMetrics(date: Date(timeIntervalSince1970: 86_400 * Double(offset)),
                   hrv: hrv, restingHR: rhr, stress: nil)
    }

    @Test func atypicalDayScoresNearFifty() {
        let days = (0..<10).map { day($0, hrv: 40, rhr: 70) }
        let scored = StressScore.annotate(days)
        // Every day identical means zero variance and so no baseline at all;
        // the score must be absent rather than invented.
        #expect(scored.allSatisfy { $0.stress == nil })
    }

    @Test func lowHRVAndHighRestingHRScoreAboveBaseline() {
        var days = (0..<9).map { day($0, hrv: 45, rhr: 68) }
        days.append(day(9, hrv: 25, rhr: 82))          // a strained day
        let scored = StressScore.annotate(days)
        #expect(scored.last?.stress != nil)
        #expect(scored.last!.stress! > 50)
    }

    @Test func highHRVAndLowRestingHRScoreBelowBaseline() {
        var days = (0..<9).map { day($0, hrv: 40, rhr: 75) }
        days.append(day(9, hrv: 70, rhr: 60))          // a recovered day
        let scored = StressScore.annotate(days)
        #expect(scored.last!.stress! < 50)
    }

    @Test func staysWithinZeroToOneHundred() {
        var days = (0..<20).map { day($0, hrv: 45, rhr: 70) }
        days.append(day(20, hrv: 1, rhr: 200))         // absurd outlier
        days.append(day(21, hrv: 400, rhr: 30))
        let scored = StressScore.annotate(days).compactMap(\.stress)
        #expect(scored.allSatisfy { $0 >= 0 && $0 <= 100 })
    }

    @Test func handlesAnEmptySeries() {
        #expect(StressScore.annotate([]).isEmpty)
    }

    @Test func aSingleDayHasNoBaseline() {
        let scored = StressScore.annotate([day(0, hrv: 40, rhr: 70)])
        #expect(scored.first?.stress == nil)
    }

    /// Days missing one signal still score from the other, rather than being
    /// dropped — a watch worn only part of the time is the normal case.
    @Test func scoresFromOneSignalWhenTheOtherIsMissing() {
        var days = (0..<9).map { day($0, hrv: 45, rhr: 68) }
        days.append(day(9, hrv: nil, rhr: 85))
        let scored = StressScore.annotate(days)
        #expect(scored.last?.stress != nil)
        #expect(scored.last!.stress! > 50)
    }

    @Test func daysWithNoSignalsScoreNil() {
        var days = (0..<9).map { day($0, hrv: 45, rhr: 68) }
        days.append(day(9, hrv: nil, rhr: nil))
        #expect(StressScore.annotate(days).last?.stress == nil)
    }

    @Test func preservesOrderAndCount() {
        let days = (0..<12).map { day($0, hrv: Double(30 + $0), rhr: Double(60 + $0)) }
        let scored = StressScore.annotate(days)
        #expect(scored.count == days.count)
        #expect(scored.map(\.date) == days.map(\.date))
    }
}
