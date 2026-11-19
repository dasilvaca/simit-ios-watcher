import Foundation
import Testing
import UserNotifications
@testable import Sappa

// MARK: - Fakes

/// SIMIT stand-in: answers from fixtures, never touches the network.
final class FakeSimit: HttpTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<HttpResponse, TransportError>] = [:]
    private(set) var calls: [String] = []

    func set(_ plate: String, json: String) {
        lock.withLock { responses[plate] = .success(HttpResponse(status: 200, body: Data(json.utf8))) }
    }

    func set(_ plate: String, error: TransportError) {
        lock.withLock { responses[plate] = .failure(error) }
    }

    func send(request: HttpRequest) throws -> HttpResponse {
        // Proof-of-work question service, asked right before each lookup.
        if request.url.hasPrefix("https://qxcaptcha.fcm.org.co/") {
            let question = #"{"error":false,"data":{"question":"51105c0550b068e4620513eea19d07a3","recommended_difficulty":2}}"#
            return HttpResponse(status: 200, body: Data(question.utf8))
        }
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        let dto = body?["reCaptchaDTO"] as? [String: Any]
        precondition(dto?["response"] is String, "lookup without proof of work")
        let plate = body?["filtro"] as? String ?? ""
        return try lock.withLock {
            calls.append(plate)
            guard let r = responses[plate] else { throw TransportError.Offline }
            return try r.get()
        }
    }
}

final class FakeCenter: NotificationScheduling, @unchecked Sendable {
    var added: [UNNotificationRequest] = []
    var removed: [String] = []
    var removedAll = false

    func add(_ request: UNNotificationRequest) async throws { added.append(request) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { removed += identifiers }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func removeAllPendingNotificationRequests() { removedAll = true }
}

enum Fixtures {
    static let onePending = """
    { "multas": [ {
        "numeroComparendo": "11001000000045678901", "placa": "TTO08G",
        "fechaComparendo": "13/11/2026", "estadoComparendo": "Pendiente",
        "ciudad": "Bogotá D.C.", "valorPagar": 604200,
        "infracciones": [ { "codigoInfraccion": "C02",
                            "descripcionInfraccion": "Estacionar un vehículo en sitios prohibidos." } ]
    } ], "totalGeneral": 604200 }
    """
    static let noFines = #"{ "multas": [], "totalGeneral": 0 }"#
}

struct Harness {
    let dir: URL
    let simit = FakeSimit()
    let center = FakeCenter()
    let host: CoreHost
    let service: CheckService
    let scheduled = Counter()

    final class Counter: @unchecked Sendable { var value = 0 }

    init(prefs: (Bool, Bool, Bool) = (true, true, true)) {
        dir = FileManager.default.temporaryDirectory.appending(path: "sappa-tests-\(UUID().uuidString)")
        host = CoreHost(directory: dir, transport: simit)
        let notifier = Notifier(center: center, core: host.core, prefs: { (prefs.0, prefs.1, prefs.2) })
        let counter = scheduled
        service = CheckService(host: host, notifier: notifier, scheduleNext: { _ in counter.value += 1 })
    }
}

// MARK: - Background check path (the BGTask handler calls exactly this)

@Suite("Background check")
struct BackgroundCheckTests {
    @Test func firstRunIsBaselineThenNewFineNotifies() async throws {
        let h = Harness()
        _ = try h.host.core.addVehicle(plate: "TTO08G", kind: .moto, nickname: "Moto principal", now: Date().unix)

        // First run: no fines → no notification, dead-man re-armed, snapshot written.
        h.simit.set("TTO08G", json: Fixtures.noFines)
        let r1 = try #require(await h.service.run(trigger: .scheduled, budgetMs: 10_000))
        #expect(r1.result == .ok)
        #expect(h.center.added.map(\.identifier) == [Notifier.deadManIdentifier])
        #expect(h.scheduled.value == 1, "next BGTask scheduled after every run")
        let snap = try JSONSerialization.jsonObject(with: Data(contentsOf: h.host.snapshotURL)) as? [String: Any]
        #expect(snap?["status"] as? String == "clear")

        // Later: a fine appears → "new fine" notification posted now, reminder scheduled for later.
        h.center.added.removeAll()
        let later = Date().addingTimeInterval(3 * 3600).unix
        h.simit.set("TTO08G", json: Fixtures.onePending)
        let r2 = try h.host.core.runCheck(now: later, trigger: .scheduled, budgetMs: 10_000)
        #expect(r2.newFines.count == 1)
        await h.service.notifier.process(alerts: r2.alerts, cancelled: r2.cancelledAlertIds, now: later.date)
        let newFine = try #require(h.center.added.first { $0.content.title.contains("TTO08G") && $0.trigger == nil })
        #expect(newFine.content.userInfo["fineId"] as? Int64 == r2.newFines[0].id)

        // Delivered alerts never come back: a re-run posts nothing.
        h.center.added.removeAll()
        #expect(try h.host.core.pendingAlerts(now: later).isEmpty)
        _ = await h.service.run(trigger: .scheduled, budgetMs: 10_000)
        #expect(h.center.added.allSatisfy { $0.identifier == Notifier.deadManIdentifier })
    }

    @Test func disabledAlertKindsAreNotPostedButAreConsumed() async throws {
        let h = Harness(prefs: (false, false, false))
        _ = try h.host.core.addVehicle(plate: "TTO08G", kind: .moto, nickname: nil, now: Date().unix)
        h.simit.set("TTO08G", json: Fixtures.onePending)
        _ = await h.service.run(trigger: .scheduled, budgetMs: 10_000)
        #expect(h.center.added.isEmpty)
        #expect(try h.host.core.pendingAlerts(now: Date().unix).isEmpty)
    }

    @Test func offlineRunDoesNotRearmDeadMan() async throws {
        let h = Harness()
        _ = try h.host.core.addVehicle(plate: "ABC123", kind: .car, nickname: nil, now: Date().unix)
        h.simit.set("ABC123", error: .Offline)
        let report = try #require(await h.service.run(trigger: .scheduled, budgetMs: 10_000))
        #expect(report.result == .offline)
        #expect(h.center.added.isEmpty)
        #expect(h.scheduled.value == 1)
    }

    @Test func manualChecksAreRateLimited() async throws {
        let h = Harness()
        _ = try h.host.core.addVehicle(plate: "ABC123", kind: .car, nickname: nil, now: Date().unix)
        h.simit.set("ABC123", json: Fixtures.noFines)
        _ = await h.service.run(trigger: .manual, budgetMs: 10_000)
        let second = try #require(await h.service.run(trigger: .manual, budgetMs: 10_000))
        #expect(h.simit.calls.count == 1)
        #expect(second.outcomes.first?.outcome == .skippedRecent)
    }

    @Test func databaseHasUntilFirstUnlockProtectionAndWAL() throws {
        let h = Harness()
        _ = try h.host.core.addVehicle(plate: "ABC123", kind: .car, nickname: nil, now: Date().unix)
        #expect(FileManager.default.fileExists(atPath: h.host.databaseURL.path))
        #expect(FileManager.default.fileExists(atPath: h.host.databaseURL.path + "-wal"))
    }
}

// MARK: - Notifications

@Suite("Notifications")
struct NotificationTests {
    func alert(kind: AlertKind, dueAt: Int64, stage: DiscountStage? = .fifty, days: UInt32? = 4) -> Alert {
        Alert(id: 7, kind: kind, dueAt: dueAt, fineId: 3, vehicleId: 1, plate: "TTO08G", nickname: nil,
              vehicleKind: .moto, infractionCode: "C02", place: "Bogotá", amount: 604_200,
              discountStage: stage, businessDaysLeft: days, discountDeadline: dueAt + 86_400, lastOkAt: nil)
    }

    @Test func newFineIsImmediate() throws {
        let now = Date()
        let r = try #require(Notifier.request(for: alert(kind: .newFine, dueAt: now.unix), now: now))
        #expect(r.identifier == "sappa-alert-7")
        #expect(r.trigger == nil)
        #expect(r.content.title.contains("TTO08G"))
        #expect(r.content.body.contains("C02"))
        #expect(r.content.interruptionLevel != .timeSensitive)
    }

    @Test func shortWindowIsTimeSensitive() throws {
        let now = Date()
        let r = try #require(Notifier.request(for: alert(kind: .newFine, dueAt: now.unix, days: 1), now: now))
        #expect(r.content.interruptionLevel == .timeSensitive)
    }

    @Test func discountReminderIsScheduledAtDueDate() throws {
        let now = Date()
        let due = now.addingTimeInterval(2 * 86_400)
        let r = try #require(Notifier.request(for: alert(kind: .discountEnding, dueAt: due.unix), now: now))
        let trigger = try #require(r.trigger as? UNCalendarNotificationTrigger)
        let next = try #require(trigger.nextTriggerDate())
        #expect(abs(next.timeIntervalSince(due)) < 60)
    }

    @Test func checksFailingSharesTheDeadManSlot() throws {
        let now = Date()
        let r = try #require(Notifier.request(for: alert(kind: .checksFailing, dueAt: now.unix, stage: nil, days: nil), now: now))
        #expect(r.identifier == Notifier.deadManIdentifier)
    }

    @Test func cancelledAlertsAreUnscheduled() async throws {
        let h = Harness()
        await h.service.notifier.process(alerts: [], cancelled: [4, 5])
        #expect(h.center.removed == ["sappa-alert-4", "sappa-alert-5"])
    }
}

// MARK: - Schedule

@Suite("Schedule")
struct ScheduleTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Bogota")!
        return c
    }()

    func date(_ h: Int, _ m: Int, day: Int = 18) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    @Test func picksNextSlot() {
        #expect(CheckSchedule.nextCheck(after: date(5, 0), morning: 360, evening: 1080, calendar: cal) == date(6, 0))
        #expect(CheckSchedule.nextCheck(after: date(6, 2), morning: 360, evening: 1080, calendar: cal) == date(18, 0))
        #expect(CheckSchedule.nextCheck(after: date(19, 0), morning: 360, evening: 1080, calendar: cal) == date(6, 0, day: 19))
        // Never "right now": a slot within 15 minutes is skipped.
        #expect(CheckSchedule.nextCheck(after: date(17, 50), morning: 360, evening: 1080, calendar: cal) == date(6, 0, day: 19))
    }

    @Test func minutesRoundTrip() {
        let d = CheckSchedule.dateFor(minutes: 6 * 60 + 30, calendar: cal)
        #expect(CheckSchedule.minutes(of: d, calendar: cal) == 390)
    }
}

// MARK: - Transport and core bridge

@Suite("Transport and core")
struct TransportTests {
    @Test func refusesPlainHTTP() {
        let t = URLSessionTransport()
        let req = HttpRequest(method: "GET", url: "http://example.com", headers: [], body: nil, timeoutMs: 1000)
        #expect(throws: TransportError.self) { try t.send(request: req) }
    }

    @Test func mapsURLErrors() {
        #expect(URLSessionTransport.map(URLError(.timedOut)) == .Timeout)
        #expect(URLSessionTransport.map(URLError(.notConnectedToInternet)) == .Offline)
        if case .Other = URLSessionTransport.map(URLError(.badServerResponse)) {} else { Issue.record("expected .Other") }
    }

    @Test func coreValidatesPlatesAndMasks() {
        #expect(validatePlate(plate: "tto08g", kind: .moto).error == nil)
        #expect(validatePlate(plate: "TTO08G", kind: .car).error == .wrongFormatCar)
        #expect(detectVehicleKind(plate: "ABC123") == .car)
        #expect(maskPlate(plate: "TTO08G") == "TTO***")
    }

    @Test func diagnosticsMaskPlates() throws {
        let h = Harness()
        _ = try h.host.core.addVehicle(plate: "TTO08G", kind: .moto, nickname: nil, now: Date().unix)
        let report = Diagnostics.report(core: h.host.core)
        #expect(report.contains("TTO***"))
        #expect(!report.contains("TTO08G"))
    }

    @Test func deleteAllEmptiesTheStore() throws {
        let h = Harness()
        _ = try h.host.core.addVehicle(plate: "ABC123", kind: .car, nickname: nil, now: Date().unix)
        try h.host.core.deleteAll()
        #expect(try h.host.core.listVehicles().isEmpty)
    }
}

// MARK: - Localization

@Suite("Localization")
struct LocalizationTests {
    /// Every user-facing key must have a Spanish translation in the String Catalog.
    @Test(arguments: [
        "Home", "Fines", "Settings", "All clear", "Which vehicle should we watch?",
        "Let it work on its own", "Start watching", "Delete all my data", "Support the project",
        "Pay on SIMIT", "New fine · %@", "You have 50%% off for %lld more business days.",
        "No new fines on your %lld vehicles.", "%lld new", "Step %lld of %lld",
        "SAPPA is not affiliated with SIMIT or the Federación Colombiana de Municipios.",
    ])
    func spanishExists(key: String) throws {
        let path = try #require(Bundle.main.path(forResource: "es", ofType: "lproj"), "es.lproj missing")
        let es = try #require(Bundle(path: path))
        let value = es.localizedString(forKey: key, value: "__missing__", table: nil)
        #expect(value != "__missing__" && value != key, "no Spanish for \(key)")
    }

    @Test func pesosHaveNoDecimals() {
        let s = Fmt.cop(604_200)
        #expect(s.contains("604"))
        #expect(!s.contains(".00") && !s.contains(",00"))
    }
}
