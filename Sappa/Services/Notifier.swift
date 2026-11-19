import Foundation
import UserNotifications
import SappaCore

/// The bits of `UNUserNotificationCenter` the notifier uses, so tests can swap in a fake.
protocol NotificationScheduling: AnyObject {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}

extension UNUserNotificationCenter: NotificationScheduling {}

/// Turns the core's alert codes into localized local notifications.
final class Notifier: @unchecked Sendable {
    static let deadManIdentifier = "sappa-deadman"
    /// Silent-failure alarm: fires if no successful run re-arms it within 26 h.
    static let deadManDelay: TimeInterval = 26 * 3600

    private let center: NotificationScheduling
    private let core: SappaCore
    private let prefs: () -> (newFine: Bool, discount: Bool, failing: Bool)

    init(center: NotificationScheduling = UNUserNotificationCenter.current(),
         core: SappaCore,
         prefs: @escaping () -> (newFine: Bool, discount: Bool, failing: Bool) = {
             (Prefs.notifyNewFine, Prefs.notifyDiscount, Prefs.notifyFailing)
         }) {
        self.center = center
        self.core = core
        self.prefs = prefs
    }

    static func identifier(for alertId: Int64) -> String { "sappa-alert-\(alertId)" }

    /// Posts or schedules every alert, removes cancelled ones, then tells the core they were handled.
    func process(alerts: [Alert], cancelled: [Int64], now: Date = Date()) async {
        let cancelledIds = cancelled.map(Self.identifier(for:))
        if !cancelledIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: cancelledIds)
        }
        let enabled = prefs()
        var handled: [Int64] = []
        for alert in alerts {
            let wanted: Bool
            switch alert.kind {
            case .newFine: wanted = enabled.newFine
            case .discountEnding: wanted = enabled.discount
            case .checksFailing: wanted = enabled.failing
            }
            if wanted, let request = Self.request(for: alert, now: now) {
                do {
                    try await center.add(request)
                } catch {
                    // Not authorized: the fine is still in the app; do not retry forever.
                }
            }
            handled.append(alert.id)
        }
        if !handled.isEmpty {
            try? core.markAlertsDelivered(ids: handled, now: now.unix)
        }
    }

    /// Called after every successful run.
    func rearmDeadMan(now: Date = Date()) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.deadManIdentifier])
        guard prefs().failing else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "SAPPA can’t check SIMIT")
        content.body = String(localized: "No successful check in the last 24 hours. Open the app to check now.")
        content.sound = .default
        content.threadIdentifier = "sappa-health"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.deadManDelay, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.deadManIdentifier, content: content, trigger: trigger))
    }

    func removeAll() {
        center.removeAllPendingNotificationRequests()
    }

    static func request(for alert: Alert, now: Date) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.sound = .default
        var identifier = identifier(for: alert.id)

        switch alert.kind {
        case .newFine:
            guard let plate = alert.plate else { return nil }
            content.title = String(localized: "New fine · \(plate)")
            content.body = L10n.fineSummary(code: alert.infractionCode, place: alert.place,
                                            stage: alert.discountStage, daysLeft: alert.businessDaysLeft)
            content.threadIdentifier = "sappa-fines"
            if let days = alert.businessDaysLeft, alert.discountStage == .fifty, days <= 2 {
                content.interruptionLevel = .timeSensitive
            }
        case .discountEnding:
            guard let plate = alert.plate else { return nil }
            let days = Int(alert.businessDaysLeft ?? 1)
            content.title = alert.discountStage == .twentyFive
                ? String(localized: "25% discount ends soon · \(plate)")
                : String(localized: "50% discount ends soon · \(plate)")
            content.body = String(localized: "\(days) business days left to pay with the discount.")
            content.threadIdentifier = "sappa-fines"
            content.interruptionLevel = .timeSensitive
        case .checksFailing:
            identifier = deadManIdentifier // same slot as the dead-man's switch: never two of them
            content.title = String(localized: "SAPPA can’t check SIMIT")
            content.body = String(localized: "No successful check in the last 24 hours. Open the app to check now.")
            content.threadIdentifier = "sappa-health"
        }
        if let fineId = alert.fineId {
            content.userInfo = ["fineId": fineId]
        }

        let due = alert.dueAt.date
        let trigger: UNNotificationTrigger?
        if due.timeIntervalSince(now) > 60 {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            trigger = nil // deliver now
        }
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
