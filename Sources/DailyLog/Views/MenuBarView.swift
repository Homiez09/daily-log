import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct MenuBarView: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @State private var showingHistory = false
    @State private var showingSettings = false
    // Measured height of the dashboard content; lets the popover shrink to fit instead of leaving a
    // large empty area when only a few sections are enabled.
    @State private var dashboardContentHeight: CGFloat = 460

    private let popoverWidth: CGFloat = 340
    /// Tall enough for the whole dashboard on big screens, but never taller than the display can show.
    private var maxDashboardHeight: CGFloat {
        min(600, (NSScreen.main?.visibleFrame.height ?? 800) - 190)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingHistory {
                HistoryView(trackingVM: trackingVM, isPresented: $showingHistory)
                    .frame(height: 560)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else if showingSettings {
                SettingsView(trackingVM: trackingVM, isPresented: $showingSettings)
                    .frame(height: 560)
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            } else {
                VStack(spacing: 0) {
                    if trackingVM.gameState.uiSettings.showHeader {
                        HeaderView(gameState: trackingVM.gameState)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 10)
                    }

                    ScrollView {
                        GlassGroup(spacing: 14) {
                            VStack(spacing: 14) {
                                if trackingVM.gameState.uiSettings.showSystemMonitor {
                                    SystemDashboardView(monitor: trackingVM.systemMonitor, trackingVM: trackingVM)
                                }

                                if trackingVM.gameState.uiSettings.showProcessMonitor {
                                    ProcessMonitorView(trackingVM: trackingVM)
                                }

                                if trackingVM.gameState.uiSettings.showProductiveApps {
                                    ProductiveAppsSectionView(trackingVM: trackingVM)
                                }

                                if trackingVM.gameState.uiSettings.showHistoryButton {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showingHistory = true
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "chart.bar.fill")
                                            Text("Lifetime History")
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity)
                                        .glassCard(cornerRadius: 18, tint: .blue)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                            }
                        )
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: min(max(dashboardContentHeight, 120), maxDashboardHeight))
                    .onPreferenceChange(ContentHeightKey.self) { dashboardContentHeight = $0 }

                    FooterView(showingSettings: $showingSettings)
                }
            }
        }
        .frame(width: popoverWidth)
        .environment(\.glassCardsEnabled, trackingVM.gameState.uiSettings.liquidGlassCards)
        .popoverBackground()
    }
}

struct HeaderView: View {
    var gameState: GameState
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(gameState.exp) / CGFloat(gameState.requiredExpForNextLevel))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Text("\(gameState.level)")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Productivity Level")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                HStack(spacing: 4) {
                    Text(gameState.progressTimeText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("\(gameState.totalLifetimeTimeText) Total")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassCard(cornerRadius: 24)
    }
}

struct ProductiveAppsSectionView: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @State private var showingAddApp = false
    @State private var showAllApps = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PRODUCTIVE APPS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Button(action: { showingAddApp.toggle() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingAddApp, arrowEdge: .top) {
                    AddAppPopover(trackingVM: trackingVM)
                }
            }
            
            if trackingVM.gameState.productiveApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Add apps to earn rewards")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                let sortedApps = trackingVM.sortedProductiveApps
                let displayCount = showAllApps ? sortedApps.count : 5
                let appsToShow = Array(sortedApps.prefix(displayCount))
                
                VStack(spacing: 0) {
                    ForEach(appsToShow) { app in
                        AppRow(app: app, trackingVM: trackingVM)
                        if app != appsToShow.last {
                            Divider().opacity(0.3).padding(.leading, 32)
                        }
                    }
                }
                
                if trackingVM.gameState.productiveApps.count > 5 {
                    Button(action: { withAnimation { showAllApps.toggle() } }) {
                        Text(showAllApps ? "Show Less" : "Show More (\(trackingVM.gameState.productiveApps.count - 5)+)")
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }
}

struct AppRow: View {
    let app: ProductiveApp
    @ObservedObject var trackingVM: TrackingViewModel
    
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: trackingVM.getIcon(for: app.bundleId))
                .resizable()
                .frame(width: 22, height: 22)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(app.appName)
                    .font(.system(size: 12, weight: .semibold))
                if trackingVM.isProductiveAppActive && trackingVM.currentAppName == app.appName {
                    Text("Tracking Active")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            Text(formatTime(trackingVM.getTimeToday(for: app.bundleId)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            
            Button(action: { trackingVM.removeProductiveApp(bundleId: app.bundleId) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }
}

struct FooterView: View {
    @Binding var showingSettings: Bool
    
    var body: some View {
        HStack {
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { 
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSettings = true 
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct AddAppPopover: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ADD PRODUCTIVE APP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider().opacity(0.5)
            
            let apps = trackingVM.getAddableApps()
            
            if apps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No addable apps found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: 280, height: 300)
            } else {
                List(apps) { app in
                    Button(action: {
                        withAnimation {
                            trackingVM.addProductiveApp(bundleId: app.id, name: app.name)
                            dismiss()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(app.id)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(width: 280, height: 350)
            }
            
            Divider().opacity(0.5)
            Text("Only apps with windows can be tracked")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.vertical, 10)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ProcessMonitorView: View {
    @ObservedObject var trackingVM: TrackingViewModel

    private var cpuThreshold: Double { trackingVM.gameState.uiSettings.cpuAlertThreshold }
    private var ramThreshold: Double { trackingVM.gameState.uiSettings.ramAlertThreshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP PROCESSES")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1)

            let processes = Array(trackingVM.systemMonitor.stats.topProcesses.prefix(6))

            if processes.isEmpty {
                Text("Gathering process data...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                        ProcessRow(process: process, cpuThreshold: cpuThreshold, ramThreshold: ramThreshold)
                        if index < processes.count - 1 {
                            Divider().opacity(0.3).padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }
}

struct ProcessRow: View {
    let process: ProcessStats
    let cpuThreshold: Double
    let ramThreshold: Double

    private var isOverCPU: Bool { process.cpuUsage >= cpuThreshold }
    private var isOverRAM: Bool { process.ramUsageMB >= ramThreshold }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = process.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 18, height: 18)
                    .foregroundColor(.secondary)
            }

            Text(process.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            if isOverCPU || isOverRAM {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
            }

            Spacer()

            Text(String(format: "%.0f%%", process.cpuUsage))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isOverCPU ? .red : .secondary)
                .frame(width: 42, alignment: .trailing)

            Text(formatRAM(process.ramUsageMB))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isOverRAM ? .red : .secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private func formatRAM(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1fGB", mb / 1024) : String(format: "%.0fMB", mb)
    }
}

