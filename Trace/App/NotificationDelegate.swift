import Foundation
import SwiftData
import UserNotifications

/// Receives notification taps and logs the activity they name.
///
/// A tap can arrive with the app closed, so this owns its own ModelContainer
/// rather than borrowing a view's environment.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let container: ModelContainer?

    init(container: ModelContainer?) {
        self.container = container
        super.init()
    }

    /// Show the prompt even if the app happens to be open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let typed = (response as? UNTextInputNotificationResponse)?.userText

        guard let logged = PromptReply.activity(
            actionIdentifier: response.actionIdentifier,
            typedText: typed,
            userInfo: response.notification.request.content.userInfo
        ) else { return }

        await log(logged)
    }

    @MainActor
    private func log(_ logged: PromptReply.Logged) async {
        guard let container else { return }
        let context = ModelContext(container)
        context.insert(Activity(label: logged.label, start: logged.start, end: logged.end))
        try? context.save()
    }
}
