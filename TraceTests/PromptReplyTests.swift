import Testing
import Foundation
@testable import Trace

/// Turning a tapped notification into an activity. The property that matters:
/// an elevated-heart-rate reply must be backdated to the window the watch
/// flagged, not to the moment you happened to tap it — otherwise the activity
/// lands on the Today chart nowhere near the readings that caused the prompt.
struct PromptReplyTests {

    private let start = Date(timeIntervalSince1970: 1_757_000_000)
    private var end: Date { start.addingTimeInterval(600) }
    private var now: Date { start.addingTimeInterval(3_000) }

    private var elevatedInfo: [AnyHashable: Any] {
        [PromptID.startKey: start.timeIntervalSince1970,
         PromptID.endKey: end.timeIntervalSince1970]
    }

    @Test func aQuickReplyCarriesItsLabel() {
        #expect(PromptReply.label(actionIdentifier: PromptID.labelActionPrefix + "Study",
                                  typedText: nil) == "Study")
    }

    @Test func typedTextIsUsedForTheOtherAction() {
        #expect(PromptReply.label(actionIdentifier: PromptID.otherAction,
                                  typedText: "  Piano  ") == "Piano")
    }

    @Test func emptyTypedTextLogsNothing() {
        #expect(PromptReply.label(actionIdentifier: PromptID.otherAction, typedText: "   ") == nil)
        #expect(PromptReply.label(actionIdentifier: PromptID.otherAction, typedText: nil) == nil)
    }

    /// Dismissing or merely opening the notification must not log anything.
    @Test func nonLabelActionsLogNothing() {
        #expect(PromptReply.label(actionIdentifier: UNNotificationDismissActionIdentifierStub,
                                  typedText: nil) == nil)
        #expect(PromptReply.label(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
                                  typedText: nil) == nil)
    }

    @Test func anElevatedReplyIsBackdatedToTheFlaggedWindow() {
        let logged = PromptReply.activity(
            actionIdentifier: PromptID.labelActionPrefix + "Study",
            typedText: nil,
            userInfo: elevatedInfo,
            now: now
        )
        #expect(logged?.start == start)
        #expect(logged?.end == end)
        #expect(logged?.label == "Study")
    }

    @Test func aCheckInLogsTheWindowJustEnding() {
        let logged = PromptReply.activity(
            actionIdentifier: PromptID.labelActionPrefix + "Reading",
            typedText: nil,
            userInfo: [:],
            now: now
        )
        #expect(logged?.end == now)
        #expect(logged?.start == now.addingTimeInterval(-PromptReply.checkInWindow))
    }

    /// A malformed window must fall back rather than produce an inverted or
    /// zero-length activity.
    @Test func anInvertedWindowFallsBackToACheckIn() {
        let logged = PromptReply.activity(
            actionIdentifier: PromptID.labelActionPrefix + "Study",
            typedText: nil,
            userInfo: [PromptID.startKey: end.timeIntervalSince1970,
                       PromptID.endKey: start.timeIntervalSince1970],
            now: now
        )
        #expect(logged?.end == now)
        #expect((logged?.end.timeIntervalSince(logged!.start) ?? 0) > 0)
    }

    @Test func aRepliedActivityAlwaysHasPositiveDuration() {
        for info in [elevatedInfo, [:] as [AnyHashable: Any]] {
            let logged = PromptReply.activity(
                actionIdentifier: PromptID.labelActionPrefix + "Study",
                typedText: nil, userInfo: info, now: now)
            #expect(logged != nil)
            #expect(logged!.end > logged!.start)
        }
    }
}

/// The real constant lives in UserNotifications; naming it here keeps the test
/// target from importing the framework just for a string.
private let UNNotificationDismissActionIdentifierStub = "com.apple.UNNotificationDismissActionIdentifier"
