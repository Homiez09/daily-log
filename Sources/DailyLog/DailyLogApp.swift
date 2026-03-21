import SwiftUI
import AppKit

struct MetricData {
    let label: String
    let value: String
    let progress: Double
    let color: Color
}

@main
struct DailyLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var trackingVM = TrackingViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(trackingVM: trackingVM)
        } label: {
            MenuBarAdvancedLabel(trackingVM: trackingVM)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarAdvancedLabel: View {
    @ObservedObject var trackingVM: TrackingViewModel
    
    var body: some View {
        MetricRow(data: getMetricData(for: trackingVM.gameState.uiSettings.menuBarLeading))
    }
    
    private func getMetricData(for metric: MenuBarMetric) -> MetricData {
        let stats = trackingVM.systemMonitor.stats
        switch metric {
        case .cpu:
            return MetricData(label: "C", value: "\(safeInt(stats.cpuUsage))%", progress: safeProgress(stats.cpuUsage / 100), color: .pink)
        case .gpu:
            return MetricData(label: "G", value: "\(safeInt(stats.gpuUsage))%", progress: safeProgress(stats.gpuUsage / 100), color: .purple)
        case .ram:
            let p = stats.ramTotal > 0 ? stats.ramUsed / stats.ramTotal : 0
            return MetricData(label: "R", value: String(format: "%.0fG", stats.ramUsed), progress: safeProgress(p), color: .blue)
        case .storage:
            let p = stats.diskTotal > 0 ? stats.diskUsed / stats.diskTotal : 0
            return MetricData(label: "D", value: String(format: "%.0f%%", p * 100), progress: safeProgress(p), color: .orange)
        case .temp:
            return MetricData(label: "T", value: "\(safeInt(stats.temperature))°", progress: safeProgress(stats.temperature / 100), color: .red)
        case .network:
            let total = stats.networkDownload + stats.networkUpload
            let val = total >= 1.0 ? String(format: "%.1fM", total) : String(format: "%.0fK", total * 1024)
            return MetricData(label: "N", value: val, progress: safeProgress(min(total / 10, 1.0)), color: .green)
        }
    }
    
    private func safeInt(_ value: Double) -> Int {
        if value.isNaN || value.isInfinite { return 0 }
        return Int(value)
    }
    
    private func safeProgress(_ value: Double) -> Double {
        if value.isNaN || value.isInfinite { return 0 }
        return min(max(value, 0), 1)
    }
}

struct MetricRow: View {
    let data: MetricData
    let barWidth: CGFloat = 20.0 // Fixed width for reliability on Menu Bar
    
    var body: some View {
        HStack(spacing: 4) {
            // Text Part
            Text("\(data.label) \(data.value)")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(data.color)
                .frame(width: 32, alignment: .trailing)
            
            // Solid Progress Bar (Manual Width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(data.color.opacity(0.2))
                    .frame(width: barWidth, height: 3)
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(data.color)
                    .frame(width: barWidth * CGFloat(data.progress), height: 3)
            }
        }
        .frame(height: 8)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
