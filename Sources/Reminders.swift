import Foundation
import UserNotifications

/// Reminders for todo due dates.
/// Notifications are scheduled in macOS: they arrive on time even when WorkHub is closed.
/// Every time the todos are saved, they are all rescheduled (new, changed, removed, completed due dates).
enum TodoReminders {
    private static let prefix = "todo|"
    private static var generation = 0

    static func reschedule(from json: String) {
        guard let state = parse(json), let todos = state["todos"] as? [[String: Any]] else { return }
        var listNames: [String: String] = [:]
        for list in (state["lists"] as? [[String: Any]]) ?? [] {
            if let id = list["id"] as? String, let name = list["name"] as? String { listNames[id] = name }
        }
        generation += 1
        let token = generation
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            DispatchQueue.main.async {
                guard token == generation else { return }   // a newer save arrived in the meantime
                center.removePendingNotificationRequests(withIdentifiers: old)
                var completed: [String] = []
                let now = Date()
                for todo in todos {
                    guard let id = todo["id"] as? String else { continue }
                    if (todo["done"] as? Bool) == true {
                        completed.append(prefix + id)
                        continue
                    }
                    guard let dueMs = (todo["due"] as? NSNumber)?.doubleValue else { continue }
                    let due = Date(timeIntervalSince1970: dueMs / 1000)
                    guard due > now else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = (todo["text"] as? String) ?? "Todo"
                    if let listId = todo["listId"] as? String, let list = listNames[listId] {
                        content.body = "Due now in \(list)"
                    } else {
                        content.body = "Due now"
                    }
                    content.sound = .default
                    content.categoryIdentifier = "todo"   // "Mark as done" and "Remind me in 1 hour" buttons
                    content.userInfo = ["service": "todos", "jsId": id]
                    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                    center.add(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger),
                               withCompletionHandler: nil)
                }
                // Completed todos also disappear from Notification Center
                center.removeDeliveredNotifications(withIdentifiers: completed)
            }
        }
    }

    /// Open todos past their due date (badge on the Todos icon).
    static func overdueCount(in json: String) -> Int {
        guard let todos = parse(json)?["todos"] as? [[String: Any]] else { return 0 }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return todos.filter { todo in
            (todo["done"] as? Bool) != true && ((todo["due"] as? NSNumber)?.doubleValue ?? .infinity) <= nowMs
        }.count
    }

    private static func parse(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
