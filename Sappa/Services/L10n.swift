import Foundation

/// Localized text built from the core's codes and values (the core never returns sentences).
enum L10n {
    static func fineSummary(code: String?, place: String?, stage: DiscountStage?, daysLeft: UInt32?) -> String {
        let what: String
        switch (code, place) {
        case let (code?, place?): what = String(localized: "\(code) in \(place).")
        case let (code?, nil): what = "\(code)."
        default: what = ""
        }
        let days = Int(daysLeft ?? 0)
        let discount: String
        switch stage {
        case .fifty?: discount = String(localized: "You have 50% off for \(days) more business days.")
        case .twentyFive?: discount = String(localized: "You have 25% off for \(days) more business days.")
        default: discount = String(localized: "The discount period is over.")
        }
        return what.isEmpty ? discount : "\(what) \(discount)"
    }

    static func vehicleName(_ vehicle: Vehicle) -> String {
        if let nickname = vehicle.nickname, !nickname.isEmpty { return nickname }
        return kindName(vehicle.kind)
    }

    static func kindName(_ kind: VehicleKind) -> String {
        switch kind {
        case .car: String(localized: "Car")
        case .moto: String(localized: "Motorcycle")
        }
    }

    static func runResult(_ result: RunResult?) -> String {
        switch result {
        case .ok?: String(localized: "OK")
        case .offline?: String(localized: "No connection")
        case .blocked?: String(localized: "Blocked by SIMIT")
        case .error?: String(localized: "Error")
        case nil: String(localized: "In progress")
        }
    }

    static func errorClass(_ error: ErrorClass) -> String {
        switch error {
        case .offline: String(localized: "No connection")
        case .timeout: String(localized: "SIMIT took too long")
        case .blocked: String(localized: "SIMIT asked for verification")
        case .http: String(localized: "SIMIT returned an error")
        case .parse: String(localized: "SIMIT’s answer changed format")
        case .interrupted: String(localized: "Interrupted by iOS")
        case .storage: String(localized: "Storage error")
        }
    }

    static func trigger(_ trigger: CheckTrigger) -> String {
        switch trigger {
        case .scheduled: String(localized: "Automatic")
        case .manual: String(localized: "Manual")
        }
    }

    static func stageTitle(_ stage: DiscountStage) -> String {
        switch stage {
        case .fifty: String(localized: "50% discount")
        case .twentyFive: String(localized: "25% discount")
        case .full: String(localized: "Full amount")
        }
    }

    static func status(_ status: FineStatus) -> String {
        switch status {
        case .pending: String(localized: "Pending payment")
        case .paid: String(localized: "Paid")
        case .other: String(localized: "In process")
        }
    }
}

/// Formatting for pesos, dates and times in the phone's language.
enum Fmt {
    static let bogota = TimeZone(identifier: "America/Bogota") ?? .current

    static func cop(_ amount: Int64) -> String {
        Decimal(amount).formatted(.currency(code: "COP").precision(.fractionLength(0)))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "today 6:02 AM", "yesterday 6:00 PM", or "Nov 12, 6:00 PM".
    static func dayAndTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let t = time(date)
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "today \(t)") }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return String(localized: "yesterday \(t)")
        }
        if let tm = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tm) {
            return String(localized: "tomorrow \(t)")
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        if now.timeIntervalSince(date) < 60 { return String(localized: "just now") }
        return f.localizedString(for: date, relativeTo: now)
    }

    /// Deadline dates are Bogotá dates, whatever the phone's time zone.
    static func deadline(_ ts: Int64) -> String {
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = bogota
        return ts.date.formatted(style)
    }

    static func shortDate(_ ts: Int64) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = bogota
        return ts.date.formatted(style)
    }
}
