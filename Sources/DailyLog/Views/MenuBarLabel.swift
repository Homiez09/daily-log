import SwiftUI
import AppKit

/// One metric as shown in the menu bar.
struct MenuBarCell: Identifiable {
    let metric: MenuBarMetric
    let title: String
    let value: String
    let progress: Double
    let history: [Double]
    let color: Color

    var id: String { metric.rawValue }

    static func make(metric: MenuBarMetric, stats: SystemStats, monitor: SystemMonitorManager) -> MenuBarCell {
        let progress = monitor.progressValue(for: metric, stats: stats)
        let history = monitor.metricHistory[metric] ?? []
        let color = Palette.color(for: metric)

        func cell(_ title: String, _ value: String) -> MenuBarCell {
            MenuBarCell(metric: metric, title: title, value: value, progress: progress, history: history, color: color)
        }

        switch metric {
        case .cpu: return cell("CPU", Format.percent(stats.cpuUsage))
        case .gpu: return cell("GPU", Format.percent(stats.gpuUsage))
        case .ram: return cell("RAM", "\(Format.gigabytes(stats.ramUsed))G")
        case .storage: return cell("DISK", Format.percent(stats.diskTotal > 0 ? stats.diskUsed / stats.diskTotal * 100 : 0))
        case .temp: return cell("TEMP", stats.temperature.map { String(format: "%.0f°", $0) } ?? "—")
        case .network: return cell("NET", Format.compactRate(stats.networkDownload + stats.networkUpload))
        case .fan:
            let rpm = stats.fans.isEmpty ? nil : stats.fans.map(\.currentRPM).reduce(0, +) / Double(stats.fans.count)
            return cell("FAN", rpm.map { String(format: "%.0f", $0) } ?? "—")
        }
    }
}

/// The view that gets rasterised into the status item. `MenuBarExtra` only draws plain `Text`/`Image`
/// in its label (shapes and gauges are silently dropped), so the whole thing is rendered to a bitmap.
struct MenuBarLabelContent: View {
    let cells: [MenuBarCell]
    let style: MenuBarStyle
    let colored: Bool

    var body: some View {
        HStack(spacing: 9) {
            ForEach(cells) { cell in
                MenuBarCellView(cell: cell, style: style, colored: colored)
            }
        }
        .padding(.horizontal, 1)
        .frame(height: 18)
    }
}

private struct MenuBarCellView: View {
    let cell: MenuBarCell
    let style: MenuBarStyle
    let colored: Bool

    // Template images are tinted by the system from the alpha channel only, so draw in black.
    private var ink: Color { colored ? cell.color : .black }

    var body: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: -1) {
                Text(cell.title)
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(ink.opacity(colored ? 0.9 : 0.62))
                Text(cell.value)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
            }
            // Wide enough for "1986"/"11.9G"; never truncate a reading in the menu bar.
            .frame(minWidth: 30, alignment: .leading)
            .fixedSize()

            graph
        }
    }

    @ViewBuilder
    private var graph: some View {
        switch style {
        case .solid:
            ZStack(alignment: .bottom) {
                Capsule().fill(ink.opacity(0.26))
                Capsule().fill(ink).frame(height: max(3, 16 * CGFloat(cell.progress)))
            }
            .frame(width: 5, height: 16)
        case .line:
            HistoryGraph(values: cell.history, color: ink, filled: false, lineWidth: 1.4)
                .frame(width: 30, height: 16)
        case .wave:
            HistoryGraph(values: cell.history, color: ink, filled: true, lineWidth: 1.4)
                .frame(width: 30, height: 16)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @ObservedObject var monitor: SystemMonitorManager

    var body: some View {
        let settings = trackingVM.gameState.uiSettings
        var metrics = [settings.menuBarLeading]
        if settings.showTrailingMetric, settings.menuBarTrailing != settings.menuBarLeading {
            metrics.append(settings.menuBarTrailing)
        }
        let cells = metrics.map { MenuBarCell.make(metric: $0, stats: monitor.stats, monitor: monitor) }
        let content = MenuBarLabelContent(cells: cells, style: settings.menuBarStyle, colored: settings.menuBarColored)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let image = renderer.nsImage {
            image.isTemplate = !settings.menuBarColored
            return Image(nsImage: image)
        }
        return Image(systemName: "gauge")
    }
}
