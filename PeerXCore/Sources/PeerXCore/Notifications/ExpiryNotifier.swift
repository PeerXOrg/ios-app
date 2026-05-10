import Foundation
import UserNotifications

public enum ExpiryNotifier {
    private static let warningIdentifier = "me.nickaroot.peerx.pass.expiry.warning"
    private static let leadTime: TimeInterval = 12 * 60 * 60

    public static func requestProvisionalAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        } catch {
            AppLog.flow.error("notif provisional auth failed: \(String(describing: error), privacy: .public)")
        }
    }

    public static func scheduleWarning(expiresAt: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [warningIdentifier])

        let fireDate = expiresAt.addingTimeInterval(-leadTime)
        guard fireDate > Date() else {
            AppLog.flow.info("notif skipped (warning time \(fireDate.description, privacy: .public) already past)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your campus pass expires soon", bundle: .module)
        content.body = String(localized: "Open PeerX to renew. Tap the pass in Wallet to see the new code.", bundle: .module)
        content.sound = nil
        content.interruptionLevel = .passive

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: warningIdentifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            AppLog.flow.info("notif scheduled for \(fireDate.description, privacy: .public)")
        } catch {
            AppLog.flow.error("notif schedule failed: \(String(describing: error), privacy: .public)")
        }
    }

    public static func cancelWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [warningIdentifier])
    }
}
