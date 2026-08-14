import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Programmation de notification locale injectable (§5, backlog V2, DRO-84) — jamais testée
/// contre le vrai `UNUserNotificationCenter` (nécessite une autorisation système interactive,
/// absente en environnement de test) ; une implémentation factice permet de vérifier la logique
/// d'appel sans jamais dépendre du framework réel.
public protocol NotificationScheduling: Sendable {
    /// `nil` si l'utilisateur n'a jamais accordé l'autorisation (ou l'a refusée) — l'appelant ne
    /// doit alors jamais présenter de rappel comme programmé.
    func requestAuthorizationIfNeeded() async -> Bool
    func scheduleReminder(identifier: String, title: String, body: String, at date: Date) async
    func cancelReminder(identifier: String) async
}

#if canImport(UserNotifications)
public struct SystemNotificationScheduler: NotificationScheduling {
    public init() {}

    public func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    public func scheduleReminder(identifier: String, title: String, body: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    public func cancelReminder(identifier: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
#endif
