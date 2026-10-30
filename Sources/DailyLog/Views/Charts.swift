import SwiftUI

/// Circular gauge with the value in the middle.
struct RingGauge: View {
    let progress: Double
    let color: Color
    let valueText: String
    var lineWidth: CGFloat = 7

    private var clamped: Double { progress.isFinite ? min(max(progress, 0), 1) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(clamped, 0.05))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(valueText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}

/// Maps samples (0...1) into a rect. Utilisation is drawn on a fixed 0–100 % scale so a wobble between
/// 24 % and 25 % is not stretched into a dramatic wave.
private func chartPoints(_ values: [Double], in rect: CGRect) -> [CGPoint] {
    let samples = values.count >= 2 ? values : [values.first ?? 0, values.first ?? 0]
    let stepX = rect.width / CGFloat(samples.count - 1)
    let inset: CGFloat = 1
    let height = rect.height - inset * 2
    return samples.enumerated().map { index, value in
        let clamped = value.isFinite ? min(max(value, 0), 1) : 0
        return CGPoint(x: rect.minX + CGFloat(index) * stepX, y: rect.maxY - inset - CGFloat(clamped) * height)
    }
}

struct LineShape: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = chartPoints(values, in: rect)
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }
}

struct AreaShape: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = chartPoints(values, in: rect)
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: rect.maxY))
        points.forEach { path.addLine(to: $0) }
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// History graph used both in the dashboard and (rendered to an image) in the menu bar.
struct HistoryGraph: View {
    let values: [Double]
    let color: Color
    var filled: Bool = true
    var lineWidth: CGFloat = 1.6

    var body: some View {
        ZStack {
            if filled {
                AreaShape(values: values)
                    .fill(LinearGradient(colors: [color.opacity(0.38), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
            LineShape(values: values)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// One vertical bar per logical core; efficiency cores are amber, performance cores use the CPU blue.
/// (Keep charts free of continuous animation: anything that redraws every frame inside a glass group
/// makes the whole group re-render and costs tens of percent of a core.)
struct CoreBars: View {
    let usages: [Double]
    let types: [CPUCoreType]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(usages.enumerated()), id: \.offset) { index, usage in
                let type = index < types.count ? types[index] : .unknown
                let color = type == .efficiency ? Palette.efficiencyCore : Palette.cpu
                VStack(spacing: 3) {
                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.16))
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(4, proxy.size.height * CGFloat(min(max(usage / 100, 0), 1))))
                        }
                    }
                    .frame(height: 36)
                }
                if type == .efficiency, index + 1 < types.count, types[index + 1] != .efficiency {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 36).padding(.horizontal, 2)
                }
            }
        }
    }
}

/// Stacked bar mirroring Activity Monitor's memory breakdown.
struct MemoryBar: View {
    let app: Double
    let wired: Double
    let compressed: Double
    let cached: Double
    let total: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 1.5) {
                segment(app, Palette.ram, width)
                segment(wired, Color(red: 1.0, green: 0.35, blue: 0.30), width)
                segment(compressed, Color(red: 0.75, green: 0.30, blue: 0.75), width)
                segment(cached, Color.secondary.opacity(0.35), width)
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .frame(height: 7)
    }

    private func segment(_ value: Double, _ color: Color, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: total > 0 ? max(0, width * CGFloat(min(value / total, 1))) : 0)
    }
}
