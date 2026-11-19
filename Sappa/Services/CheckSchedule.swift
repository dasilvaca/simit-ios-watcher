import BackgroundTasks
import Foundation
import SappaCore

/// Picks the next check time ("roughly 6:00 and 18:00"); iOS decides the exact minute.
enum CheckSchedule {
    /// Next morning/evening slot strictly after `date` (+ a small margin so we never ask for "now").
    static func nextCheck(after date: Date = Date(),
                          morning: Int = Prefs.morningMinutes,
                          evening: Int = Prefs.eveningMinutes,
                          calendar: Calendar = .current) -> Date {
        let from = date.addingTimeInterval(15 * 60)
        let slots = Set([morning, evening]).sorted()
        let startOfDay = calendar.startOfDay(for: from)
        for dayOffset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
            for minutes in slots {
                if let candidate = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                   candidate > from {
                    return candidate
                }
            }
        }
        return from.addingTimeInterval(12 * 3600)
    }

    static func dateFor(minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// `BGAppRefreshTask` plumbing. Registered at launch; rescheduled after every run and app open.
enum BackgroundScheduler {
    static var taskIdentifier: String { (Bundle.main.bundleIdentifier ?? "sappa") + ".check" }
    /// iOS gives about 30 s per wake; keep a margin for notifications and the snapshot.
    static let budgetMs: UInt32 = 22_000

    static func register(service: CheckService) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh, service: service)
        }
    }

    static func handle(_ task: BGAppRefreshTask, service: CheckService) {
        scheduleNext() // keep the chain alive even if this run is killed
        let completion = CompletionOnce(task)
        let work = Task {
            let report = await service.run(trigger: .scheduled, budgetMs: budgetMs)
            completion.complete(success: report != nil)
        }
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }

    static func scheduleNext(after date: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = CheckSchedule.nextCheck(after: date)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator and denied Background App Refresh end up here; manual checks still work.
        }
    }
}

private final class CompletionOnce: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var done = false

    init(_ task: BGTask) { self.task = task }

    func complete(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        task.setTaskCompleted(success: success)
    }
}
