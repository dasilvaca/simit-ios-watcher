import Foundation
import SappaCore

/// Owns the one `SappaCore` instance and the directory its files live in.
///
/// The SQLite file is opened only by the core. It lives in the App Group container (so a future
/// widget extension can read the JSON snapshot next to it) with "until first unlock" protection so
/// background runs work while the phone is locked.
final class CoreHost: @unchecked Sendable {
    static let shared: CoreHost = {
        #if DEBUG
        if DemoData.isEnabled { return DemoData.makeHost() }
        #endif
        return CoreHost()
    }()

    let core: SappaCore
    let directory: URL

    static let databaseName = "sappa.sqlite"
    static let snapshotName = "widget-snapshot.json"

    var databaseURL: URL { directory.appending(path: Self.databaseName) }
    var snapshotURL: URL { directory.appending(path: Self.snapshotName) }

    convenience init() {
        self.init(directory: Self.defaultDirectory(), transport: URLSessionTransport())
    }

    init(directory: URL, transport: HttpTransport) {
        self.directory = directory
        let fm = FileManager.default
        try? fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        Self.protect(directory)

        let config = defaultConfig(dbPath: directory.appending(path: Self.databaseName).path, userAgent: Self.userAgent)
        do {
            core = try SappaCore(config: config, transport: transport)
        } catch {
            // Unreadable database: keep it aside for diagnosis and start empty rather than crash-looping.
            let db = directory.appending(path: Self.databaseName)
            let aside = directory.appending(path: "sappa-corrupt-\(Int(Date().timeIntervalSince1970)).sqlite")
            try? fm.moveItem(at: db, to: aside)
            do {
                core = try SappaCore(config: config, transport: transport)
            } catch {
                fatalError("SAPPA core could not open its database: \(error)")
            }
        }
        protectFiles()
    }

    /// Re-applies file protection to the database and its WAL/SHM side files.
    func protectFiles() {
        for suffix in ["", "-wal", "-shm"] {
            Self.protect(directory.appending(path: Self.databaseName + suffix))
        }
    }

    private static func protect(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    static var appGroupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "SappaAppGroup") as? String
    }

    static func defaultDirectory() -> URL {
        let fm = FileManager.default
        if let group = appGroupIdentifier,
           let container = fm.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return container.appending(path: "Library/Application Support/Sappa", directoryHint: .isDirectory)
        }
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Sappa", directoryHint: .isDirectory)
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "SAPPA/\(version) (iOS)"
    }
}

extension Date {
    var unix: Int64 { Int64(timeIntervalSince1970) }
}

extension Int64 {
    var date: Date { Date(timeIntervalSince1970: TimeInterval(self)) }
}
