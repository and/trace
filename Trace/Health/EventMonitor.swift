import Foundation
import HealthKit
import UserNotifications

/// Watches for the Watch's own high-heart-rate events and asks what you were
/// doing.
///
/// It observes `highHeartRateEvent` rather than raw heart rate deliberately.
/// Heart rate produces thousands of samples a day and its observers are
/// documented as unreliable; this fires roughly four times a day, so background
/// delivery has no trouble with it.
///
/// The threshold itself belongs to watchOS — Settings › Heart › High Heart Rate,
/// minimum 100 bpm. An app cannot set it or pick a lower one.
/// Identifiers shared with the notification delegate. Plain constants, kept
/// outside the actor so they can be read from anywhere.
enum PromptID {
    static let elevatedCategory = "TRACE_ELEVATED_HR"
    static let checkInCategory = "TRACE_CHECK_IN"
    static let labelActionPrefix = "TRACE_LABEL_"
    static let otherAction = "TRACE_LABEL_OTHER"

    /// Carried on the notification so a reply can backdate the activity to the
    /// window the watch actually flagged.
    static let startKey = "eventStart"
    static let endKey = "eventEnd"
}

@MainActor
final class EventMonitor: ObservableObject {


    private let store = HKHealthStore()
    private let eventType = HKCategoryType(.highHeartRateEvent)
    private var observer: HKObserverQuery?
    private var anchor: HKQueryAnchor?

    /// Labels offered as one-tap replies. Kept small: iOS shows only the first
    /// few without expanding the notification.
    private var quickLabels: [String] = []

    // MARK: - Setup

    func start(labels: [String]) async {
        quickLabels = Array(labels.prefix(3))
        guard HKHealthStore.isHealthDataAvailable() else { return }

        await registerCategories()
        guard await requestNotificationPermission() else { return }

        do {
            try await store.requestAuthorization(toShare: [], read: [eventType])
        } catch {
            return
        }

        try? await store.enableBackgroundDelivery(for: eventType, frequency: .immediate)
        observe()
    }

    private func observe() {
        guard observer == nil else { return }

        let query = HKObserverQuery(sampleType: eventType, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor in
                await self?.handleNewEvents()
                // Must be called, or HealthKit throttles delivery off entirely.
                completion()
            }
        }
        observer = query
        store.execute(query)
    }

    // MARK: - Reacting

    private func handleNewEvents() async {
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: eventType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, added, _, newAnchor, _ in
                Task { @MainActor in self?.anchor = newAnchor }
                continuation.resume(returning: (added as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        // Only events from the last few hours are worth asking about; anything
        // older arrived from a backfill and you will not remember it.
        let cutoff = Date().addingTimeInterval(-4 * 3600)
        for sample in samples where sample.startDate > cutoff {
            await notify(start: sample.startDate, end: sample.endDate)
        }
    }

    private func notify(start: Date, end: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Heart rate was up"

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        content.body = "\(formatter.string(from: start))–\(formatter.string(from: end)) — what were you doing?"
        content.categoryIdentifier = PromptID.elevatedCategory
        content.userInfo = [
            PromptID.startKey: start.timeIntervalSince1970,
            PromptID.endKey: end.timeIntervalSince1970,
        ]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "elevated-\(Int(start.timeIntervalSince1970))",
            content: content,
            trigger: nil        // deliver now
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Notification plumbing

    private func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private func registerCategories() async {
        var actions = quickLabels.map {
            UNNotificationAction(identifier: PromptID.labelActionPrefix + $0, title: $0, options: [])
        }
        actions.append(
            UNTextInputNotificationAction(
                identifier: PromptID.otherAction,
                title: "Something else…",
                options: [],
                textInputButtonTitle: "Log",
                textInputPlaceholder: "What were you doing?"
            )
        )

        let elevated = UNNotificationCategory(
            identifier: PromptID.elevatedCategory,
            actions: actions,
            intentIdentifiers: []
        )
        let checkIn = UNNotificationCategory(
            identifier: PromptID.checkInCategory,
            actions: actions,
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([elevated, checkIn])
    }
}
