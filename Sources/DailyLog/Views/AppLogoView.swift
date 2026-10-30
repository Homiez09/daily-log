import SwiftUI

/// The DailyLog mark: an activity ring (the level/EXP gauge) with a heartbeat line (the live system
/// monitor). `Resources/make_icon.swift` draws the same geometry for the .icns / Icon Composer files,
/// so the in-app logo and the Dock/Finder icon stay identical.
struct AppLogoView: View {
    var size: CGFloat = 28

    private static let gradient = LinearGradient(
        colors: [Color(red: 0.36, green: 0.36, blue: 1.00), Color(red: 0.08, green: 0.78, blue: 0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Self.gradient)

            // Gauge track + progress arc (270° sweep, opening at the bottom).
            Circle()
                .trim(from: 0, to: 0.75)
                .rotation(.degrees(135))
                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                .frame(width: size * 0.56, height: size * 0.56)
            Circle()
                .trim(from: 0, to: 0.52)
                .rotation(.degrees(135))
                .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                .frame(width: size * 0.56, height: size * 0.56)

            Path { path in
                let points: [(CGFloat, CGFloat)] = [(0.32, 0.50), (0.42, 0.50), (0.47, 0.38), (0.54, 0.63), (0.59, 0.50), (0.68, 0.50)]
                for (index, point) in points.enumerated() {
                    let cgPoint = CGPoint(x: point.0 * size, y: point.1 * size)
                    index == 0 ? path.move(to: cgPoint) : path.addLine(to: cgPoint)
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.08, green: 0.30, blue: 0.80).opacity(0.35), radius: size * 0.12, y: size * 0.05)
        .accessibilityLabel("DailyLog")
    }
}
