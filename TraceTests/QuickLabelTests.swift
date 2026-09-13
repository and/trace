import Testing
import Foundation
@testable import Trace

/// Quick-pick ordering. The row previously always led with the built-in
/// defaults, so the labels actually being used sat behind ones never touched.
struct QuickLabelTests {

    private func use(_ label: String, _ daysAgo: Int, times: Int = 1) -> [(label: String, start: Date)] {
        let day = Date(timeIntervalSince1970: 1_757_000_000 - Double(daysAgo) * 86_400)
        return (0..<times).map { (label: label, start: day.addingTimeInterval(Double($0) * 60)) }
    }

    @Test func withNoHistoryTheBuiltInOrderIsKept() {
        #expect(QuickLabel.ordered(usage: []) == QuickLabel.all)
    }

    @Test func theMostUsedLabelComesFirst() {
        let usage = use("Meeting", 1, times: 5) + use("Study", 1, times: 2)
        let ordered = QuickLabel.ordered(usage: usage)
        #expect(ordered.first == "Meeting")
        #expect(ordered[1] == "Study")
    }

    @Test func aCustomLabelOutranksUnusedDefaults() {
        let ordered = QuickLabel.ordered(usage: use("Gym", 1, times: 3))
        #expect(ordered.first == "Gym")
    }

    @Test func tiesGoToTheMoreRecentlyUsed() {
        let usage = use("Chores", 10, times: 2) + use("Reading", 1, times: 2)
        let ordered = QuickLabel.ordered(usage: usage)
        #expect(ordered.first == "Reading")
        #expect(ordered[1] == "Chores")
    }

    @Test func usedLabelsAllPrecedeUnusedOnes() {
        let usage = use("Chores", 3, times: 1)
        let ordered = QuickLabel.ordered(usage: usage)
        #expect(ordered.first == "Chores")
        // The untouched defaults follow, still in their built-in order.
        #expect(ordered.dropFirst().first == "Study")
    }

    @Test func everyLabelAppearsExactlyOnce() {
        let usage = use("Study", 1, times: 4) + use("Gym", 2, times: 1) + use("Study", 5, times: 1)
        let ordered = QuickLabel.ordered(usage: usage)
        #expect(Set(ordered).count == ordered.count)
        #expect(Set(ordered) == Set(QuickLabel.all).union(["Gym"]))
    }

    @Test func orderingIsStableForTheSameInput() {
        let usage = use("Study", 1, times: 2) + use("Gym", 1, times: 2)
        #expect(QuickLabel.ordered(usage: usage) == QuickLabel.ordered(usage: usage))
    }
}
