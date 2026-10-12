import Cocoa
import UserNotifications

/// Native macOS notifications. A click brings you back to the service and the content that triggered it.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// (serviceId, JS notification id) — set by AppController.
    var onClick: ((String, String?) -> Void)?
    /// (button identifier, serviceId, id) — notification buttons, e.g. "todo.done".
    var onAction: ((String, String, String?) -> Void)?

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let done = UNNotificationAction(identifier: "todo.done", title: "Mark as done", options: [])
        let snooze = UNNotificationAction(identifier: "todo.snooze", title: "Remind me in 1 hour", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "todo", actions: [done, snooze], intentIdentifiers: [], options: []),
        ])
    }

    func show(identifier: String, serviceId: String, serviceName: String,
              jsId: String?, title: String, body: String, silent: Bool) {
        let content = UNMutableNotificationContent()
        if title.isEmpty {
            content.title = serviceName
        } else {
            content.title = title
            content.subtitle = serviceName
        }
        content.body = body
        if !silent { content.sound = .default }
        var info: [String: String] = ["service": serviceId]
        if let jsId = jsId { info["jsId"] = jsId }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func remove(identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // Shows the banner even when the app is in the foreground (the "you're already looking at it"
    // filter is applied earlier, in ServiceController).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let service = info["service"] as? String
        let jsId = info["jsId"] as? String
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if let service = service {
                if action == UNNotificationDefaultActionIdentifier {
                    self.onClick?(service, jsId)
                } else if action != UNNotificationDismissActionIdentifier {
                    self.onAction?(action, service, jsId)
                }
            }
            completionHandler()
        }
    }
}
