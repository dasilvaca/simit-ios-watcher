import Foundation
import UIKit

/// "Enviar reporte": a plain-text file the user shares by mail or share sheet. Plates are masked.
enum Diagnostics {
    static func report(core: SappaCore, now: Date = Date()) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("SAPPA diagnostics")
        lines.append("Generated: \(iso.string(from: now))")
        lines.append("App: \(CoreHost.appVersion) · core \(coreVersion())")
        lines.append("OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · \(UIDevice.current.model)")
        lines.append("Language: \(Locale.current.identifier)")
        lines.append("Background refresh: \(backgroundRefresh)")

        let vehicles = (try? core.listVehicles()) ?? []
        let masked = vehicles.map { "\(maskPlate(plate: $0.plate)) \($0.kind == .car ? "car" : "moto") pending=\($0.pendingFines)" }
        lines.append("Vehicles: \(vehicles.count)")
        lines.append(contentsOf: masked.map { "  \($0)" })

        if let health = try? core.health(now: now.unix, limit: 20) {
            lines.append("Health: \(health.status)")
            lines.append("Last ok: \(health.lastOkAt.map { iso.string(from: $0.date) } ?? "never")")
            lines.append("Last \(health.runs.count) runs:")
            for run in health.runs {
                let result = run.result.map { "\($0)" } ?? "running"
                let error = run.error.map { " error=\($0)" } ?? ""
                let ms = run.durationMs.map { " \($0)ms" } ?? ""
                lines.append("  \(iso.string(from: run.startedAt.date)) \(run.trigger) \(result)\(error) checked=\(run.platesChecked) remaining=\(run.platesRemaining)\(ms)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static var backgroundRefresh: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: "available"
        case .denied: "denied"
        case .restricted: "restricted"
        @unknown default: "unknown"
        }
    }

    /// Writes `contents` to a temporary file for ShareLink.
    static func temporaryFile(named name: String, contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try? Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}
