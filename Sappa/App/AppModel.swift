import Foundation
import Observation
import SwiftUI

enum AppTab: Hashable { case home, fines, settings, add }

struct FineRoute: Hashable { let id: Int64 }
struct VehicleRoute: Hashable { let id: Int64 }

/// UI state over the core. Database reads are quick and run on the main actor; checks run
/// off the main thread through `CheckService`.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(service: .shared)

    let service: CheckService
    var core: SappaCore { service.host.core }

    var vehicles: [Vehicle] = []
    var fines: [Fine] = []
    var health: Health?
    var isChecking = false
    var lastManualReport: CheckReport?
    var banner: Banner?
    var onboardingDone: Bool = Prefs.onboardingDone {
        didSet { Prefs.onboardingDone = onboardingDone }
    }

    var tab: AppTab = .home
    var homePath = NavigationPath()
    var finesPath = NavigationPath()

    enum Banner: Equatable {
        case checkedNothingNew
        case newFines(Int)
        case skippedRecent
        case failed(ErrorClass)
        case busy
    }

    init(service: CheckService) {
        self.service = service
        reload()
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "SappaDemoScreen") {
        case "fine": if let id = fines.first?.id { openFine(id) }
        case "fines": tab = .fines
        case "settings": tab = .settings
        default: break
        }
        #endif
    }

    // MARK: Derived state

    var newFinesCount: Int { vehicles.reduce(0) { $0 + Int($1.newFines) } }
    var pendingFines: [Fine] { fines.filter { $0.status == .pending } }
    var newFines: [Fine] { fines.filter(\.isNew) }

    /// The pending fine whose discount closes first.
    var mostUrgentFine: Fine? {
        let candidates = newFines.isEmpty ? pendingFines : newFines
        return candidates.min { deadline($0) < deadline($1) }
    }

    private func deadline(_ fine: Fine) -> Int64 {
        switch fine.discount.stage {
        case .fifty: fine.discount.fiftyUntil
        case .twentyFive: fine.discount.twentyFiveUntil
        case .full: .max
        }
    }

    func vehicle(_ id: Int64) -> Vehicle? { vehicles.first { $0.id == id } }
    func fine(_ id: Int64) -> Fine? { fines.first { $0.id == id } }
    func fines(for vehicleId: Int64) -> [Fine] { fines.filter { $0.vehicleId == vehicleId } }

    var nextCheck: Date { CheckSchedule.nextCheck() }

    // MARK: Loading

    func reload() {
        let now = Date().unix
        vehicles = (try? core.listVehicles()) ?? []
        fines = (try? core.listFines(vehicleId: nil, now: now)) ?? []
        health = try? core.health(now: now, limit: 14)
    }

    /// Every app open: reschedule (iOS mitigation), re-post pending alerts, refresh the snapshot.
    func appBecameActive() async {
        reload()
        BackgroundScheduler.scheduleNext()
        await service.resyncAlerts()
        service.writeSnapshot()
    }

    // MARK: Actions

    @discardableResult
    func addVehicle(plate: String, kind: VehicleKind, nickname: String?) throws -> Vehicle {
        let vehicle = try core.addVehicle(plate: plate, kind: kind, nickname: nickname, now: Date().unix)
        reload()
        service.writeSnapshot()
        return vehicle
    }

    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        guard let report = await service.run(trigger: .manual, budgetMs: 25_000) else {
            banner = .busy
            reload()
            return
        }
        lastManualReport = report
        reload()
        if !report.newFines.isEmpty {
            banner = .newFines(report.newFines.count)
        } else if let error = report.error {
            banner = .failed(error)
        } else if !report.outcomes.isEmpty, report.outcomes.allSatisfy({ $0.outcome == .skippedRecent }) {
            banner = .skippedRecent
        } else {
            banner = .checkedNothingNew
        }
    }

    func acknowledge(_ fine: Fine) {
        guard fine.isNew else { return }
        try? core.acknowledgeFine(id: fine.id, now: Date().unix)
        reload()
        service.writeSnapshot()
    }

    func markPaid(_ fine: Fine) async {
        if let cancelled = try? core.markPaid(fineId: fine.id, now: Date().unix) {
            await service.notifier.process(alerts: [], cancelled: cancelled)
        }
        reload()
        service.writeSnapshot()
    }

    /// Returns true when a reminder was scheduled.
    func remindBeforeDeadline(_ fine: Fine) async -> Bool {
        guard let alert = try? core.remindBeforeDeadline(fineId: fine.id, now: Date().unix) else { return false }
        await service.notifier.process(alerts: [alert], cancelled: [])
        return true
    }

    func rename(_ vehicle: Vehicle, to nickname: String) {
        _ = try? core.renameVehicle(id: vehicle.id, nickname: nickname)
        reload()
        service.writeSnapshot()
    }

    func remove(_ vehicle: Vehicle) async {
        if let cancelled = try? core.removeVehicle(id: vehicle.id) {
            await service.notifier.process(alerts: [], cancelled: cancelled)
        }
        homePath = NavigationPath()
        reload()
        service.writeSnapshot()
    }

    func deleteAll() {
        try? core.deleteAll()
        service.host.protectFiles()
        service.notifier.removeAll()
        Prefs.reset()
        homePath = NavigationPath()
        finesPath = NavigationPath()
        tab = .home
        reload()
        service.writeSnapshot()
        onboardingDone = false
    }

    /// Notification tap → fine detail.
    func openFine(_ id: Int64) {
        reload()
        guard fine(id) != nil else { return }
        tab = .fines
        finesPath = NavigationPath()
        finesPath.append(FineRoute(id: id))
    }
}
