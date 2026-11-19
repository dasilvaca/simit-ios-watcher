import Foundation

/// User preferences owned by the shell (the core does no scheduling and formats no text).
enum Prefs {
    enum Key {
        static let onboardingDone = "onboardingDone"
        static let morningMinutes = "morningMinutes"
        static let eveningMinutes = "eveningMinutes"
        static let notifyNewFine = "notifyNewFine"
        static let notifyDiscount = "notifyDiscount"
        static let notifyFailing = "notifyFailing"
    }

    nonisolated(unsafe) static var store: UserDefaults = {
        let defaults = CoreHost.appGroupIdentifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        defaults.register(defaults: [
            Key.onboardingDone: false,
            Key.morningMinutes: 6 * 60,
            Key.eveningMinutes: 18 * 60,
            Key.notifyNewFine: true,
            Key.notifyDiscount: true,
            Key.notifyFailing: true,
        ])
        return defaults
    }()

    static var onboardingDone: Bool {
        get { store.bool(forKey: Key.onboardingDone) }
        set { store.set(newValue, forKey: Key.onboardingDone) }
    }
    /// Minutes after midnight, local time.
    static var morningMinutes: Int {
        get { store.integer(forKey: Key.morningMinutes) }
        set { store.set(newValue, forKey: Key.morningMinutes) }
    }
    static var eveningMinutes: Int {
        get { store.integer(forKey: Key.eveningMinutes) }
        set { store.set(newValue, forKey: Key.eveningMinutes) }
    }
    static var notifyNewFine: Bool { store.bool(forKey: Key.notifyNewFine) }
    static var notifyDiscount: Bool { store.bool(forKey: Key.notifyDiscount) }
    static var notifyFailing: Bool { store.bool(forKey: Key.notifyFailing) }

    static func reset() {
        for key in [Key.onboardingDone, Key.morningMinutes, Key.eveningMinutes,
                    Key.notifyNewFine, Key.notifyDiscount, Key.notifyFailing] {
            store.removeObject(forKey: key)
        }
    }
}
