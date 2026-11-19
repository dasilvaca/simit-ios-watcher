import Foundation
import WidgetKit

/// One full background (or manual) check: core run → notifications → widget snapshot → next
/// schedule. Shared by the BGTask handler and the "Revisar ahora" button.
final class CheckService: @unchecked Sendable {
    static let shared = CheckService(host: .shared, notifier: Notifier(core: CoreHost.shared.core))

    let host: CoreHost
    let notifier: Notifier
    private let scheduleNext: @Sendable (Date) -> Void

    init(host: CoreHost,
         notifier: Notifier,
         scheduleNext: @escaping @Sendable (Date) -> Void = { BackgroundScheduler.scheduleNext(after: $0) }) {
        self.host = host
        self.notifier = notifier
        self.scheduleNext = scheduleNext
    }

    /// Returns `nil` when the core could not run (e.g. another run in progress).
    @discardableResult
    func run(trigger: CheckTrigger, budgetMs: UInt32) async -> CheckReport? {
        let core = host.core
        let started = Date()
        let report: CheckReport
        do {
            report = try await Task.detached(priority: trigger == .manual ? .userInitiated : .utility) {
                try core.runCheck(now: started.unix, trigger: trigger, budgetMs: budgetMs)
            }.value
        } catch {
            return nil
        }
        host.protectFiles()
        await notifier.process(alerts: report.alerts, cancelled: report.cancelledAlertIds)
        if report.result == .ok {
            await notifier.rearmDeadMan()
        }
        writeSnapshot()
        scheduleNext(Date())
        return report
    }

    /// Re-posts anything the core still has pending (e.g. the app was killed mid-run).
    func resyncAlerts() async {
        guard let alerts = try? host.core.pendingAlerts(now: Date().unix), !alerts.isEmpty else { return }
        await notifier.process(alerts: alerts, cancelled: [])
    }

    /// Widgets never open the database: they read this JSON.
    func writeSnapshot(now: Date = Date()) {
        let next = CheckSchedule.nextCheck(after: now).unix
        guard let json = try? host.core.widgetSnapshot(now: now.unix, nextCheckAt: next) else { return }
        try? Data(json.utf8).write(to: host.snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        WidgetCenter.shared.reloadAllTimelines()
    }
}
