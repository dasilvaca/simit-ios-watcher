import SwiftUI

/// Yellow Colombian plate chip: 2 pt black border, radius 7, Space Grotesk bold.
struct PlateChip: View {
    let plate: String
    var size: CGFloat = 15

    var body: some View {
        Text(plate)
            .font(.display(size, weight: .bold, relativeTo: .callout))
            .tracking(1)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color.sPlateInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.sPlateYellow))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.sPlateInk, lineWidth: 2))
            .accessibilityLabel(Text("Plate \(plate.map(String.init).joined(separator: " "))"))
    }
}

/// Full-width colored header with rounded bottom corners. It extends up under the navigation bar.
struct HeaderPanel<Content: View>: View {
    let tone: HeaderTone
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 26)
            .background(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: Metrics.headerRadius,
                                       bottomTrailingRadius: Metrics.headerRadius,
                                       style: .continuous)
                    .fill(tone.background)
                    .padding(.top, -600)
            }
            .foregroundStyle(tone.ink)
    }
}

struct GlassPill: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .sappaGlass(in: Capsule())
    }
}

struct StatusChip: View {
    enum Kind { case clear, new(Int), pending(Int) }
    let kind: Kind

    var body: some View {
        chip.lineLimit(1).fixedSize()
    }

    @ViewBuilder private var chip: some View {
        switch kind {
        case .clear:
            Text("No fines")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sGreenText)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.sGreenChipBg))
        case .new(let n):
            Text("\(n) new")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.sRust))
        case .pending(let n):
            Text("\(n) pending")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sRust)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.sAlertHeaderBg))
        }
    }
}

/// Rounded segments for the last runs: green ok, amber offline, rust error/blocked, grey running.
struct HealthBar: View {
    let runs: [RunSummary]
    var slots = 14

    var body: some View {
        let ordered = Array(runs.prefix(slots).reversed())
        HStack(spacing: 4) {
            ForEach(0..<slots, id: \.self) { i in
                let run: RunSummary? = i < ordered.count ? ordered[i] : nil
                Capsule()
                    .fill(color(run))
                    .frame(height: 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }

    private func color(_ run: RunSummary?) -> Color {
        switch run?.result {
        case .ok?: .sAccentGreen
        case .offline?: .sWarning
        case .blocked?, .error?: .sRust
        case nil: run == nil ? Color.sSeparator : Color.sSeparator.opacity(0.6)
        }
    }

    private var summary: String {
        let recent = runs.prefix(slots)
        let ok = recent.filter { $0.result == .ok }.count
        let offline = recent.filter { $0.result == .offline }.count
        let failed = recent.filter { $0.result == .error || $0.result == .blocked }.count
        return String(localized: "Last \(recent.count) checks: \(ok) ok, \(offline) offline, \(failed) failed")
    }
}

/// Rust progress bar for the discount window (how much of it has passed).
struct DiscountProgress: View {
    let discount: DiscountSchedule

    var fraction: Double {
        guard discount.windowBusinessDays > 0 else { return 1 }
        let used = Double(discount.windowBusinessDays) - Double(discount.businessDaysLeft)
        return min(max(used / Double(discount.windowBusinessDays), 0.04), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.sRust.opacity(0.18))
                Capsule().fill(Color.sRust).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.sTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)
    }
}

enum SimitLinks {
    /// Official SIMIT site, for payment. SAPPA does not take payments.
    static let payment = URL(string: "https://www.fcm.org.co/simit/")!
}

struct NotAffiliatedNote: View {
    var body: some View {
        Text("SAPPA is not affiliated with SIMIT or the Federación Colombiana de Municipios.")
            .font(.footnote)
            .foregroundStyle(Color.sTextSecondary)
    }
}
