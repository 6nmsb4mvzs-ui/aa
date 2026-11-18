import SwiftUI

/// Small rounded tag.
struct Tag: View {
    var text: String
    var systemImage: String? = nil
    var color: Color = Theme.textSecondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.label).tracking(0.6).textCase(.uppercase).lineLimit(1)
        }
        .foregroundStyle(filled ? Color.black : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(filled ? color : color.opacity(0.14), in: Capsule())
    }
}

/// Confidence indicator.
struct ConfidenceBadge: View {
    var level: ConfidenceLevel
    var compact = false

    var symbol: String {
        switch level {
        case .verified: return "checkmark.seal.fill"
        case .partial: return "circle.lefthalf.filled"
        case .uncertain: return "questionmark.circle"
        }
    }

    var body: some View {
        if compact {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tint(for: level))
                .accessibilityLabel(level.label)
        } else {
            Tag(text: level.label, systemImage: symbol, color: Theme.tint(for: level))
        }
    }
}

/// Banner shown whenever sample (fictional) data is on screen.
struct SampleDataBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 2) {
                Text("SAMPLE DATA").font(.label).tracking(1.2)
                Text("Fictional places for testing the interface. Turn off Demo mode in Settings for real discoveries.")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.black)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Generic centred state view (empty, error, onboarding).
struct StateMessage<Actions: View>: View {
    var systemImage: String
    var title: String
    var message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.display(26))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

extension StateMessage where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// Primary pill button style.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(prominent ? Theme.accent : Theme.surfaceHigh, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Placeholder artwork for places without photos: a quiet geometric grid
/// with the category glyph. No fabricated imagery.
struct PlaceholderArtwork: View {
    var symbol: String
    var tint: Color

    var body: some View {
        ZStack {
            Theme.surfaceRaised
            Canvas { context, size in
                let step: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
            }
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(tint.opacity(0.55))
        }
    }
}

/// Skeleton card shown while the first results load.
struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.surfaceRaised).aspectRatio(4 / 3, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceHigh).frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceHigh).frame(width: 200, height: 18)
            }
            .padding(Theme.gutter)
        }
        .cardSurface()
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
