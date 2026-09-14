import Foundation

/// Turning a tapped notification into an activity.
///
/// Pure, so the rules can be tested without a notification centre: which label
/// was chosen, and what window the activity should cover. An elevated-heart-rate
/// prompt carries the window the watch flagged, and the activity is backdated to
/// exactly that — it lands on the Today chart over the readings that caused it.
enum PromptReply {

    struct Logged: Equatable {
        let label: String
        let start: Date
        let end: Date
    }

    /// How long a check-in reply should cover when there is no flagged window.
    /// Short on purpose: you are reporting this moment, not the whole hour.
    static let checkInWindow: TimeInterval = 15 * 60

    /// The label a reply carries, from either a one-tap action or typed text.
    static func label(actionIdentifier: String, typedText: String?) -> String? {
        if actionIdentifier == PromptID.otherAction {
            let trimmed = (typedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard actionIdentifier.hasPrefix(PromptID.labelActionPrefix) else { return nil }
        let label = String(actionIdentifier.dropFirst(PromptID.labelActionPrefix.count))
        return label.isEmpty ? nil : label
    }

    /// Builds the activity a reply should create.
    static func activity(
        actionIdentifier: String,
        typedText: String?,
        userInfo: [AnyHashable: Any],
        now: Date = .now
    ) -> Logged? {
        guard let label = label(actionIdentifier: actionIdentifier, typedText: typedText) else {
            return nil
        }

        if let start = userInfo[PromptID.startKey] as? TimeInterval,
           let end = userInfo[PromptID.endKey] as? TimeInterval,
           end > start {
            return Logged(label: label,
                          start: Date(timeIntervalSince1970: start),
                          end: Date(timeIntervalSince1970: end))
        }

        // A check-in: log the window just ending, not one starting now.
        return Logged(label: label, start: now.addingTimeInterval(-checkInWindow), end: now)
    }
}
