import Testing
import Foundation
@testable import Trace

/// The day stepper. These are the cases behind the "next/previous gets stuck"
/// report: stepping must land on a real day boundary, must refuse the future,
/// and must never return a value the caller can misread as success.
struct DayCursorTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    @Test func stepsBackOneDay() {
        let now = date("2026-09-12 18:30")
        let today = cal.startOfDay(for: now)
        let back = DayCursor.step(from: today, by: -1, now: now, calendar: cal)
        #expect(back == date("2026-09-11 00:00"))
    }

    @Test func stepsForwardTowardToday() {
        let now = date("2026-09-12 18:30")
        let forward = DayCursor.step(from: date("2026-09-11 00:00"), by: 1, now: now, calendar: cal)
        #expect(forward == date("2026-09-12 00:00"))
    }

    @Test func refusesToStepIntoTheFuture() {
        let now = date("2026-09-12 18:30")
        let today = cal.startOfDay(for: now)
        #expect(DayCursor.step(from: today, by: 1, now: now, calendar: cal) == nil)
    }

    @Test func refusesAZeroStep() {
        let now = date("2026-09-12 18:30")
        #expect(DayCursor.step(from: now, by: 0, now: now, calendar: cal) == nil)
    }

    /// A step from a mid-day timestamp must normalise to midnight, or the
    /// chart's domain and its scroll anchor disagree and the plot goes blank.
    @Test func normalisesToStartOfDay() {
        let now = date("2026-09-12 18:30")
        let stepped = DayCursor.step(from: date("2026-09-12 18:30"), by: -1, now: now, calendar: cal)
        #expect(stepped == date("2026-09-11 00:00"))
    }

    @Test func todayIsAtPresentAndPastDaysAreNot() {
        let now = date("2026-09-12 18:30")
        #expect(DayCursor.isAtPresent(day: cal.startOfDay(for: now), now: now, calendar: cal))
        #expect(!DayCursor.isAtPresent(day: date("2026-09-11 00:00"), now: now, calendar: cal))
    }

    @Test func boundsSpanExactlyOneDay() {
        let bounds = DayCursor.bounds(of: date("2026-09-12 09:15"), calendar: cal)
        #expect(bounds.lowerBound == date("2026-09-12 00:00"))
        #expect(bounds.upperBound == date("2026-09-13 00:00"))
        #expect(bounds.upperBound.timeIntervalSince(bounds.lowerBound) == 86_400)
    }

    /// Walking back a week and forward again must return to the same day —
    /// the property that fails when stepping doesn't normalise.
    @Test func steppingRoundTrips() {
        let now = date("2026-09-12 18:30")
        var day = cal.startOfDay(for: now)
        for _ in 0..<7 { day = DayCursor.step(from: day, by: -1, now: now, calendar: cal)! }
        #expect(day == date("2026-09-05 00:00"))
        for _ in 0..<7 { day = DayCursor.step(from: day, by: 1, now: now, calendar: cal)! }
        #expect(day == cal.startOfDay(for: now))
    }
}
