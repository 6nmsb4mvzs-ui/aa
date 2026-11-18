import SwiftUI

/// Dark urban design tokens: black base, charcoal surfaces, muted category
/// tints and a single restrained "sodium lamp" accent.
enum Theme {
    static let background = Color.black
    static let surface = Color(red: 0.071, green: 0.071, blue: 0.078)
    static let surfaceRaised = Color(red: 0.11, green: 0.11, blue: 0.118)
    static let surfaceHigh = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let hairline = Color.white.opacity(0.08)

    static let textPrimary = Color(white: 0.96)
    static let textSecondary = Color(white: 0.64)
    static let textTertiary = Color(white: 0.44)

    /// Sodium-lamp amber.
    static let accent = Color(red: 0.86, green: 0.65, blue: 0.33)
    static let positive = Color(red: 0.48, green: 0.74, blue: 0.52)
    static let warning = Color(red: 0.88, green: 0.62, blue: 0.32)
    static let negative = Color(red: 0.86, green: 0.42, blue: 0.38)

    static let cornerRadius: CGFloat = 18
    static let gutter: CGFloat = 16

    static func tint(for category: DiscoveryCategory) -> Color {
        switch category {
        case .fashion: return Color(red: 0.80, green: 0.58, blue: 0.60)
        case .markets: return Color(red: 0.78, green: 0.64, blue: 0.40)
        case .skate: return Color(red: 0.47, green: 0.70, blue: 0.68)
        case .streetArt: return Color(red: 0.76, green: 0.48, blue: 0.68)
        case .architecture: return Color(red: 0.60, green: 0.66, blue: 0.76)
        case .photo: return Color(red: 0.66, green: 0.62, blue: 0.82)
        case .music: return Color(red: 0.40, green: 0.66, blue: 0.82)
        case .culture: return Color(red: 0.66, green: 0.72, blue: 0.46)
        case .cafes: return Color(red: 0.74, green: 0.58, blue: 0.45)
        case .food: return Color(red: 0.84, green: 0.50, blue: 0.40)
        case .hiddenGems: return accent
        case .nature: return Color(red: 0.48, green: 0.70, blue: 0.50)
        case .events: return Color(red: 0.88, green: 0.42, blue: 0.38)
        }
    }

    static func tint(for confidence: ConfidenceLevel) -> Color {
        switch confidence {
        case .verified: return positive
        case .partial: return textSecondary
        case .uncertain: return warning
        }
    }
}

extension Font {
    /// Condensed, heavy display face for place names.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.compressed)
    }

    /// Small, wide, uppercase-friendly label.
    static let label = Font.system(size: 11, weight: .semibold).width(.expanded)
    static let meta = Font.system(size: 13, weight: .medium)
    static let metaMono = Font.system(size: 13, weight: .medium).monospacedDigit()
}

extension View {
    /// Small uppercase "eyebrow" label style.
    func eyebrow(_ color: Color = Theme.textSecondary) -> some View {
        self.font(.label).tracking(1.1).textCase(.uppercase).foregroundStyle(color)
    }

    func cardSurface() -> some View {
        self.background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.hairline))
    }
}
