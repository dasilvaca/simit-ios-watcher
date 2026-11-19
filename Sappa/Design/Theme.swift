import SwiftUI
import UIKit

// Design tokens from docs/design.md, with derived dark-mode values that keep the meaning of
// green (all clear), rust (fine) and yellow (Colombian plate).

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self = Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let sBackground = Color(uiColor: .systemGroupedBackground)
    static let sSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let sTextPrimary = Color(light: 0x111111, dark: 0xF2F2F7)
    static let sTextSecondary = Color(light: 0x5C5C63, dark: 0xAEAEB2)
    static let sClearHeaderBg = Color(light: 0xD3EDDC, dark: 0x173B28)
    static let sClearInk = Color(light: 0x0E3A24, dark: 0xD3EDDC)
    static let sClearInkSecondary = Color(light: 0x24503A, dark: 0xA9D3B9)
    static let sAccentGreen = Color(light: 0x1F7A4D, dark: 0x2E9E66)
    static let sGreenText = Color(light: 0x1F6B45, dark: 0x6CCB97)
    static let sGreenChipBg = Color(light: 0xE3F3E9, dark: 0x1C3A29)
    static let sAlertHeaderBg = Color(light: 0xF4D5CB, dark: 0x4A2015)
    static let sAlertInk = Color(light: 0x4A1405, dark: 0xFBE1D8)
    static let sAlertInkSecondary = Color(light: 0x8A2812, dark: 0xF0B9A8)
    static let sRust = Color(light: 0xB4361C, dark: 0xE2603F)
    static let sRustOutline = Color(light: 0xF0B9A8, dark: 0x8A2812)
    static let sWarning = Color(light: 0xD59A2A, dark: 0xE0AE4A)
    static let sPlateYellow = Color(light: 0xF5C518, dark: 0xF5C518)
    static let sPlateInk = Color(light: 0x111111, dark: 0x111111)
    static let sSeparator = Color(light: 0xE5E5EA, dark: 0x38383A)
}

enum HeaderTone {
    case clear, alert

    var background: Color { self == .clear ? .sClearHeaderBg : .sAlertHeaderBg }
    var ink: Color { self == .clear ? .sClearInk : .sAlertInk }
    var inkSecondary: Color { self == .clear ? .sClearInkSecondary : .sAlertInkSecondary }
}

extension Font {
    /// Space Grotesk (bundled) for plates, status headlines, times, amounts. Scales with Dynamic Type.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        if UIFont(name: "SpaceGrotesk-Bold", size: size) != nil || UIFont.familyNames.contains("Space Grotesk") {
            return .custom("Space Grotesk", size: size, relativeTo: style).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }
}

enum Metrics {
    static let cardRadius: CGFloat = 26
    static let headerRadius: CGFloat = 38
    static let primaryHeight: CGFloat = 56
    static let gutter: CGFloat = 20
}

/// Primary capsule button, 56 pt, accent green.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .sAccentGreen
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Metrics.primaryHeight)
            .background(Capsule().fill(color.opacity(isEnabled ? 1 : 0.4)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var sappaPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func sappaPrimary(_ color: Color) -> PrimaryButtonStyle { PrimaryButtonStyle(color: color) }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Color.sSurface))
    }
}

extension View {
    func sappaCard() -> some View { modifier(CardBackground()) }

    /// Translucent glass: Liquid Glass on iOS 26.
    func sappaGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }
}
