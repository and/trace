import Testing
import Foundation
import SwiftData
@testable import Trace

/// The Activity model, against an in-memory store so the tests exercise the
/// real SwiftData type rather than a stand-in.
@MainActor
struct ActivityTests {

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Activity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func aNewActivityIsRunningAndHasNoHealthSample() throws {
        let activity = Activity(label: "Study")
        #expect(activity.isRunning)
        #expect(activity.end == nil)
        #expect(activity.healthSampleID == nil)
    }

    @Test func stoppingSetsDuration() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let activity = Activity(label: "Study", start: start, end: start.addingTimeInterval(5_400))
        #expect(!activity.isRunning)
        #expect(activity.duration == 5_400)
    }

    @Test func spansTwoDatesWhenCrossingMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"

        let activity = Activity(label: "Reading",
                                start: f.date(from: "2026-09-11 23:00")!,
                                end: f.date(from: "2026-09-12 01:00")!)
        #expect(activity.days(in: cal).count == 2)
    }

    @Test func persistsAndReloads() throws {
        let ctx = try context()
        let sampleID = UUID()
        let activity = Activity(label: "Deep work")
        activity.healthSampleID = sampleID
        ctx.insert(activity)
        try ctx.save()

        let loaded = try ctx.fetch(FetchDescriptor<Activity>())
        #expect(loaded.count == 1)
        #expect(loaded.first?.label == "Deep work")
        #expect(loaded.first?.healthSampleID == sampleID)
    }

    @Test func elapsedDescriptionFormatsMinutesAndHours() {
        #expect(TimeInterval(65).elapsedDescription == "1m 05s")
        #expect(TimeInterval(5_400).elapsedDescription == "1h 30m")
        #expect(TimeInterval(0).elapsedDescription == "0m 00s")
    }
}
