import SwiftUI

struct MenuBarView: View {
    @StateObject private var trackingVM = TrackingViewModel()
    @State private var showingHistory = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            if showingHistory {
                HistoryView(trackingVM: trackingVM, isPresented: $showingHistory)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else if showingSettings {
                SettingsView(trackingVM: trackingVM, isPresented: $showingSettings)
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            } else {
                VStack(spacing: 0) {
                    HeaderView(gameState: trackingVM.gameState)
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    
                    Divider().opacity(0.5)
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            ProductiveAppsSectionView(trackingVM: trackingVM)
                            
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
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        }
                        .padding()
                    }
                    
                    Divider().opacity(0.5)
                    
                    FooterView(showingSettings: $showingSettings)
                }
            }
        }
        .frame(width: 320, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct HeaderView: View {
    var gameState: GameState
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Level Circle
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
            
            // Coins Card
            HStack(spacing: 6) {
                Text("💥")
                Text("\(gameState.coins)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
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
                    Text("Add apps to earn coins")
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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct AppRow: View {
    let app: ProductiveApp
    @ObservedObject var trackingVM: TrackingViewModel
    
    var body: some View {
        HStack(spacing: 10) {
            let icon: NSImage = {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
                return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
            }()
            
            Image(nsImage: icon)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
