#if os(macOS)
import AppKit
import UserNotifications

/// "VPN dropped" banner with a Connect button that works from the notification itself.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    @MainActor static var onConnect: (() -> Void)?

    static func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        let connect = UNNotificationAction(identifier: "connect", title: L("Подключить"), options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "drop", actions: [connect], intentIdentifiers: [])])
    }

    /// Only when the window is not in front: someone looking at the app already sees the error.
    @MainActor static func notifyDropped() {
        guard UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true, !NSApp.isActive else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = L("VPN отключился")
            content.body = L("Соединение прервалось. Подключиться снова?")
            content.categoryIdentifier = "drop"
            try? await center.add(UNNotificationRequest(identifier: "dropped", content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == "connect" else { return }
        await MainActor.run { Self.onConnect?() }
    }
}
#endif
