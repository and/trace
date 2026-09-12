import Testing
import Foundation
@testable import Trace

/// Clipping activities to a day. Midnight crossings are where band drawing
/// goes wrong, and a band that survives on the wrong day is a silent bug —
/// it just draws a shaded region over unrelated heart rate.
struct BandLayoutTests {

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

    private func clip(_ start: String, _ end: String?, on day: String) -> BandSpan? {
        BandLayout.clip(
            label: "Study",
            start: date(start),
            end: end.map(date),
            toDayStarting: date(day),
            now: date("2026-09-12 18:00"),
            calendar: cal
        )
    }

    @Test func keepsAnActivityWhollyInsideTheDay() {
        let span = clip("2026-09-12 10:00", "2026-09-12 12:30", on: "2026-09-12 00:00")
        #expect(span?.start == date("2026-09-12 10:00"))
        #expect(span?.end == date("2026-09-12 12:30"))
        #expect(span?.duration == 9_000)
    }

    @Test func dropsAnActivityFromAnotherDay() {
        #expect(clip("2026-09-10 10:00", "2026-09-10 11:00", on: "2026-09-12 00:00") == nil)
    }

    @Test func trimsTheTailOfAMidnightCrossing() {
        let span = clip("2026-09-12 23:00", "2026-09-13 01:00", on: "2026-09-12 00:00")
        #expect(span?.start == date("2026-09-12 23:00"))
        #expect(span?.end == date("2026-09-13 00:00"))
    }

    @Test func trimsTheHeadOfAMidnightCrossing() {
        let span = clip("2026-09-11 23:00", "2026-09-12 01:00", on: "2026-09-12 00:00")
        #expect(span?.start == date("2026-09-12 00:00"))
        #expect(span?.end == date("2026-09-12 01:00"))
    }

    /// A session spanning a whole day should fill it, not collapse.
    @Test func clipsAnActivityThatSwallowsTheDay() {
        let span = clip("2026-09-11 08:00", "2026-09-13 08:00", on: "2026-09-12 00:00")
        #expect(span?.start == date("2026-09-12 00:00"))
        #expect(span?.end == date("2026-09-13 00:00"))
        #expect(span?.duration == 86_400)
    }

    /// An activity ending exactly at midnight belongs to the day it ran in,
    /// and must not leave a zero-width band on the next day.
    @Test func doesNotLeaveAZeroWidthBandOnTheFollowingDay() {
        #expect(clip("2026-09-11 22:00", "2026-09-12 00:00", on: "2026-09-12 00:00") == nil)
        #expect(clip("2026-09-11 22:00", "2026-09-12 00:00", on: "2026-09-11 00:00") != nil)
    }

    @Test func boundsARunningActivityWithNow() {
        let span = clip("2026-09-12 17:00", nil, on: "2026-09-12 00:00")
        #expect(span?.end == date("2026-09-12 18:00"))
    }

    @Test func dropsAnInvertedInterval() {
        #expect(clip("2026-09-12 12:00", "2026-09-12 10:00", on: "2026-09-12 00:00") == nil)
    }

    @Test func dropsAZeroLengthActivity() {
        #expect(clip("2026-09-12 10:00", "2026-09-12 10:00", on: "2026-09-12 00:00") == nil)
    }
}
