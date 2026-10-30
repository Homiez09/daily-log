import SwiftUI
import AppKit

enum Palette {
    static let cpu = Color(red: 0.22, green: 0.52, blue: 1.00)
    static let gpu = Color(red: 0.72, green: 0.33, blue: 0.90)
    static let ram = Color(red: 1.00, green: 0.60, blue: 0.16)
    static let fan = Color(red: 0.16, green: 0.78, blue: 0.74)
    static let storage = Color(red: 0.38, green: 0.36, blue: 0.90)
    static let download = Color(red: 0.20, green: 0.78, blue: 0.38)
    static let upload = Color(red: 0.05, green: 0.66, blue: 1.00)
    static let efficiencyCore = Color(red: 1.00, green: 0.78, blue: 0.20)

    /// Cool → hot ramp so the temperature tile reads at a glance.
    static func temperature(_ celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        switch celsius {
        case ..<60: return Color(red: 0.20, green: 0.78, blue: 0.38)
        case ..<75: return Color(red: 1.00, green: 0.72, blue: 0.10)
        case ..<90: return Color(red: 1.00, green: 0.48, blue: 0.14)
        default: return Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }

    static func color(for metric: MenuBarMetric) -> Color {
        switch metric {
        case .cpu: return cpu
        case .gpu: return gpu
        case .ram: return ram
        case .storage: return storage
        case .temp: return Color(red: 1.00, green: 0.42, blue: 0.30)
        case .network: return download
        case .fan: return fan
        }
    }
}

// MARK: - Surfaces
//
// The popover window itself is already system Liquid Glass on macOS 26+ (and a solid fill before
// that). Every extra `glassEffect` layered on top has to re-sample and re-refract whatever is behind
// the window — with a live video wallpaper (Aerial) that is WindowServer GPU work on every video frame,
// multiplied by the number of glass layers. So cards are cheap translucent fills by default, and real
// glass cards are an opt-in (`UISettings.liquidGlassCards`, Settings ▸ Appearance).

private struct GlassCardsEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var glassCardsEnabled: Bool {
        get { self[GlassCardsEnabledKey.self] }
        set { self[GlassCardsEnabledKey.self] = newValue }
    }
}

private struct CardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    @Environment(\.glassCardsEnabled) private var glassEnabled

    func body(content: Content) -> some View {
        if glassEnabled, #available(macOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0.opacity(0.16)) } ?? .regular
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background {
                    ZStack {
                        shape.fill(Color.primary.opacity(0.06))
                        if let tint { shape.fill(tint.opacity(0.14)) }
                    }
                }
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
                )
        }
    }
}

extension View {
    /// Card surface: cheap translucent fill by default, Liquid Glass when `glassCardsEnabled` (macOS 26+).
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Small tinted pill. Never real glass: chips sit inside cards, and glass on glass is both costly and
    /// discouraged by Apple's guidelines.
    func tintedCapsule(_ tint: Color? = nil) -> some View {
        background((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.2), in: Capsule())
    }

    /// The popover window already renders system glass on macOS 26+; older systems need a solid fill.
    @ViewBuilder
    func popoverBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self.background(Color(NSColor.windowBackgroundColor))
        }
    }
}

/// Lets glass cards blend and render together. Only does anything when real glass cards are enabled.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    @Environment(\.glassCardsEnabled) private var glassEnabled

    var body: some View {
        if glassEnabled, #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

enum Format {
    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        return "\(Int(value.rounded()))%"
    }

    static func gigabytes(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }

    static func rpm(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
    }

    /// Bytes per second → "154 KB/s", "1.2 MB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0 KB/s" }
        let kb = bytesPerSecond / 1024
        if kb < 1 { return "<1 KB/s" }
        if kb < 1000 { return String(format: "%.0f KB/s", kb) }
        let mb = kb / 1024
        if mb < 100 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.0f MB/s", mb)
    }

    /// Compact form for the menu bar: "154K", "1.2M".
    static func compactRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0K" }
        let kb = bytesPerSecond / 1024
        if kb < 1000 { return String(format: "%.0fK", kb) }
        let mb = kb / 1024
        return mb < 100 ? String(format: "%.1fM", mb) : String(format: "%.0fM", mb)
    }

    static func celsius(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f°", value)
    }
}
