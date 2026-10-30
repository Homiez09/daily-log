import SwiftUI
import HardwareKit

struct SystemDashboardView: View {
    @ObservedObject var monitor: SystemMonitorManager
    /// Only `FanModeToggle` observes it, so tracking updates don't re-render the whole dashboard.
    let trackingVM: TrackingViewModel

    private var stats: SystemStats { monitor.stats }

    var body: some View {
        GlassGroup(spacing: 12) {
            VStack(spacing: 12) {
                overviewCard

                HStack(alignment: .top, spacing: 12) {
                    temperatureTile
                    if !stats.fans.isEmpty { fanTile }
                }

                storageAndNetworkCard
            }
        }
    }

    // MARK: Overview (CPU / GPU / RAM)

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppLogoView(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("DailyLog")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("SYSTEM PERFORMANCE")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(monitor.cpuName)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .tintedCapsule(Palette.cpu)
            }

            HStack(alignment: .top, spacing: 0) {
                gauge(title: "CPU", progress: stats.cpuUsage / 100, value: Format.percent(stats.cpuUsage),
                      caption: coreSummary, color: Palette.cpu)
                gauge(title: "GPU", progress: stats.gpuUsage / 100, value: Format.percent(stats.gpuUsage),
                      caption: "Utilization", color: Palette.gpu)
                gauge(title: "RAM", progress: ramFraction, value: Format.percent(ramFraction * 100),
                      caption: "\(Format.gigabytes(stats.ramUsed)) of \(Format.gigabytes(stats.ramTotal, decimals: 0)) GB", color: Palette.ram)
            }

            VStack(alignment: .leading, spacing: 5) {
                sectionLabel("CPU · LAST \(historySeconds)s", trailing: Format.percent(stats.cpuUsage))
                HistoryGraph(values: monitor.metricHistory[.cpu] ?? [], color: Palette.cpu)
                    .frame(height: 38)
            }

            if !stats.perCoreUsage.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        sectionLabel("CORES", trailing: nil)
                        Spacer()
                        legendDot(Palette.efficiencyCore, "Efficiency")
                        legendDot(Palette.cpu, "Performance")
                    }
                    CoreBars(usages: stats.perCoreUsage, types: monitor.coreTypes)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    sectionLabel("MEMORY", trailing: nil)
                    Spacer()
                    Circle().fill(pressureColor).frame(width: 6, height: 6)
                    Text("Pressure \(pressureText)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                MemoryBar(app: stats.ramApp, wired: stats.ramWired, compressed: stats.ramCompressed, cached: stats.ramCached, total: stats.ramTotal)
                HStack(spacing: 10) {
                    legendDot(Palette.ram, "App \(Format.gigabytes(stats.ramApp)) GB")
                    legendDot(Color(red: 1.0, green: 0.35, blue: 0.30), "Wired \(Format.gigabytes(stats.ramWired)) GB")
                    legendDot(Color(red: 0.75, green: 0.30, blue: 0.75), "Comp. \(Format.gigabytes(stats.ramCompressed)) GB")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26)
    }

    private func gauge(title: String, progress: Double, value: String, caption: String, color: Color) -> some View {
        VStack(spacing: 7) {
            RingGauge(progress: progress, color: color, valueText: value)
                .frame(width: 70, height: 70)
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Temperature & fan

    private var temperatureTile: some View {
        let color = Palette.temperature(stats.temperature)
        var detailParts: [String] = []
        if let peak = stats.temperatureMax { detailParts.append("Peak \(Format.celsius(peak))") }
        if let ssd = stats.ssdTemperature { detailParts.append("SSD \(Format.celsius(ssd))") }
        return MetricTile(
            title: "TEMP",
            icon: Image(systemName: "thermometer.medium"),
            value: stats.temperature.map { String(format: "%.0f", $0) } ?? "—",
            unit: stats.temperature == nil ? "" : "°C",
            detail: detailParts.isEmpty ? (stats.temperature == nil ? "No sensor" : "CPU die") : detailParts.joined(separator: " · "),
            progress: stats.temperature.map { $0 / 110 },
            color: color,
            accessory: EmptyView()
        )
    }

    private var fanTile: some View {
        let fans = stats.fans
        let averageRPM = fans.map(\.currentRPM).reduce(0, +) / Double(fans.count)
        let averageFraction = fans.map(\.fraction).reduce(0, +) / Double(fans.count)
        let smcManual = fans.contains { $0.isManual }
        let detail = fans.count > 1
            ? fans.map { "F\($0.index + 1) \(Format.rpm($0.currentRPM))" }.joined(separator: " · ")
            : "\(Int((averageFraction * 100).rounded()))% of max"
        return MetricTile(
            title: "FAN",
            icon: Image(systemName: "fan.fill"),
            value: Format.rpm(averageRPM),
            unit: "RPM",
            detail: detail,
            progress: averageFraction,
            color: Palette.fan,
            accessory: FanModeToggle(trackingVM: trackingVM, controller: trackingVM.fanController, smcManual: smcManual)
        )
    }

    // MARK: Storage & network

    private var storageAndNetworkCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive.fill").font(.system(size: 10)).foregroundStyle(Palette.storage)
                    sectionLabel("STORAGE", trailing: nil)
                }
                Text("\(Format.gigabytes(stats.diskUsed)) GB")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("of \(Format.gigabytes(stats.diskTotal)) GB")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                ProgressCapsule(progress: stats.diskTotal > 0 ? stats.diskUsed / stats.diskTotal : 0, color: Palette.storage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1).padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 10)).foregroundStyle(Palette.upload)
                    sectionLabel("NETWORK", trailing: nil)
                }
                networkRow(symbol: "arrow.down.circle.fill", color: Palette.download, rate: stats.networkDownload)
                networkRow(symbol: "arrow.up.circle.fill", color: Palette.upload, rate: stats.networkUpload)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The divider is a flexible shape; without this it would stretch the card to fill any spare height.
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private func networkRow(symbol: String, color: Color, rate: Double) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(color)
            Text(Format.rate(rate))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Helpers

    private var ramFraction: Double {
        stats.ramTotal > 0 ? min(max(stats.ramUsed / stats.ramTotal, 0), 1) : 0
    }

    private var historySeconds: Int { max((monitor.metricHistory[.cpu]?.count ?? 0) * 2, 2) }

    private var coreSummary: String {
        let efficiency = monitor.coreTypes.filter { $0 == .efficiency }.count
        let performance = monitor.coreTypes.filter { $0 == .performance }.count
        if efficiency + performance == 0 { return "\(stats.perCoreUsage.count) cores" }
        return "\(performance)P + \(efficiency)E"
    }

    private var pressureText: String {
        switch stats.memoryPressure {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    private var pressureColor: Color {
        switch stats.memoryPressure {
        case .normal: return Palette.download
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func sectionLabel(_ text: String, trailing: String?) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            if let trailing {
                Spacer()
                Text(trailing)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ProgressCapsule: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, proxy.size.width * CGFloat(progress.isFinite ? min(max(progress, 0), 1) : 0)))
            }
        }
        .frame(height: 6)
    }
}

/// Compact glass tile: icon, big value, one line of detail, and a progress capsule.
struct MetricTile<Icon: View, Accessory: View>: View {
    let title: String
    let icon: Icon
    let value: String
    let unit: String
    let detail: String
    let progress: Double?
    let color: Color
    let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                icon
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                accessory
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let progress {
                ProgressCapsule(progress: progress, color: color)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: color)
    }
}

/// One-tap BOOST switch in the fan tile: dim while macOS runs the fans, lit orange while they run at
/// 100 % of their range. A manual speed set from Settings below 100 % shows as MANUAL; tapping a lit
/// chip hands the fans back to macOS.
struct FanModeToggle: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @ObservedObject var controller: FanController
    /// The SMC readout, so an override by another tool still shows when our helper is not connected.
    let smcManual: Bool

    private var isManual: Bool {
        controller.appliedMode == .manual || (controller.status != .connected && smcManual)
    }

    private var isBoost: Bool {
        isManual && trackingVM.gameState.uiSettings.fanManualFraction >= 0.999
    }

    var body: some View {
        Button {
            if isManual { trackingVM.setFanMode(.auto) } else { trackingVM.setFanMode(.manual, fraction: 1) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isManual ? "bolt.fill" : "bolt")
                    .font(.system(size: 8, weight: .bold))
                Text(isManual && !isBoost ? "MANUAL" : "BOOST")
                    .font(.system(size: 8, weight: .heavy))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isManual ? Color.orange : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isManual ? Color.orange.opacity(0.2) : Color.primary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(isManual ? Color.orange.opacity(0.5) : Color.primary.opacity(0.15), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(controller.isBusy ? 0.5 : 1)
        .disabled(controller.isBusy)
        .help(controller.lastError ?? (controller.status == .authorizing
            ? "Waiting for administrator approval…"
            : isManual ? "Click to give the fans back to macOS (AUTO)." : "Click to run the fans at full speed (BOOST)."))
    }
}
