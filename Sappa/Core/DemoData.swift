#if DEBUG
import Foundation

/// DEBUG only: launch with `-SappaDemo YES` to get two seeded vehicles (one with a new fine)
/// from a fake transport, in a throwaway directory. Never contacts SIMIT.
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "SappaDemo") }

    static func makeHost() -> CoreHost {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sappa-demo")
        try? FileManager.default.removeItem(at: dir)
        let transport = DemoTransport()
        let host = CoreHost(directory: dir, transport: transport)
        let core = host.core
        let now = Date()
        _ = try? core.addVehicle(plate: "TTO08G", kind: .moto, nickname: "Moto principal", now: now.addingTimeInterval(-86_400).unix)
        _ = try? core.addVehicle(plate: "ABC123", kind: .car, nickname: "Carro", now: now.addingTimeInterval(-86_400).unix)
        _ = try? core.runCheck(now: now.addingTimeInterval(-13 * 3600).unix, trigger: .scheduled, budgetMs: 10_000)
        transport.withFine = true
        _ = try? core.runCheck(now: now.addingTimeInterval(-3 * 3600).unix, trigger: .scheduled, budgetMs: 10_000)
        Prefs.onboardingDone = true
        return host
    }
}

private final class DemoTransport: HttpTransport, @unchecked Sendable {
    var withFine = false

    func send(request: HttpRequest) throws -> HttpResponse {
        let body = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any]
        let plate = body?["filtro"] as? String ?? ""
        let issued = Date().addingTimeInterval(-2 * 86_400)
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        let json = plate == "TTO08G" && withFine
            ? """
              { "multas": [ { "numeroComparendo": "11001000000045678901", "placa": "TTO08G",
                "fechaComparendo": "\(f.string(from: issued))", "estadoComparendo": "Pendiente",
                "ciudad": "Bogotá D.C.", "valorPagar": 604200,
                "infracciones": [ { "codigoInfraccion": "C02",
                  "descripcionInfraccion": "Estacionar un vehículo en sitios prohibidos." } ] } ] }
              """
            : #"{ "multas": [] }"#
        return HttpResponse(status: 200, body: Data(json.utf8))
    }
}
#endif
