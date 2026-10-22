import SwiftUI

/// Design tokens shared by the iPhone app, the Watch app and the complications.
/// Dark-first, soft cards and a warm orange → pink accent gradient.
enum Theme {
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.31)
    static let pink = Color(red: 0.96, green: 0.33, blue: 0.56)
    static let violet = Color(red: 0.56, green: 0.44, blue: 0.98)
    static let mint = Color(red: 0.30, green: 0.84, blue: 0.70)
    static let sky = Color(red: 0.36, green: 0.66, blue: 1.00)

    static let accentGradient = LinearGradient(
        colors: [orange, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let calmGradient = LinearGradient(
        colors: [violet, pink.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

#if os(iOS)
    static let background = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemBackground)
    static let elevated = Color(uiColor: .tertiarySystemBackground)
#else
    static let background = Color.black
    static let card = Color.white.opacity(0.10)
    static let elevated = Color.white.opacity(0.16)
#endif

    static let cornerRadius: CGFloat = 20

    static func display(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static let headline = Font.system(.headline, design: .rounded)
    static let mono = Font.system(.caption, design: .monospaced)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// A rounded square with a gradient fill and an SF Symbol, used for section icons and stat tiles.
struct GradientIcon: View {
    let systemName: String
    var size: CGFloat = 30
    var gradient: LinearGradient = Theme.accentGradient

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

enum Format {
    /// "4:05" or "1:02:33".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "5 min", "1 hr 20 min" — localized by the system.
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : (seconds >= 60 ? [.minute] : [.second])
        formatter.unitsStyle = .short
        return formatter.string(from: max(0, seconds)) ?? ""
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
