import SwiftUI

struct HistoryView: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @Binding var isPresented: Bool
    
    var lifetimeApps: [(bundleId: String, stats: AppStats)] {
        trackingVM.gameState.allTimeStats
            .sorted { $0.value.totalLifetimeTime > $1.value.totalLifetimeTime }
            .map { ($0.key, $0.value) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPresented = false 
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Spacer()
                
                Text("Lifetime History")
                    .font(.system(size: 14, weight: .bold))
                
                Spacer()
                
                // Balance
                Text("Back").font(.system(size: 13)).opacity(0)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider().opacity(0.5)
            
            if lifetimeApps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No history recorded yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(lifetimeApps, id: \.bundleId) { bid, stats in
                            HistoryCard(bid: bid, stats: stats, trackingVM: trackingVM)
                        }
                    }
                    .padding()
                }
            }
            
            Divider().opacity(0.5)
            
            // Summary Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL PRODUCTIVITY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    Text(formatTotalTime())
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func formatTotalTime() -> String {
        let total = lifetimeApps.reduce(0) { $0 + $1.stats.totalLifetimeTime }
        let hrs = Int(total) / 3600
        let mins = (Int(total) % 3600) / 60
        return "\(hrs)h \(mins)m"
    }
}

struct HistoryCard: View {
    let bid: String
    let stats: AppStats
    @ObservedObject var trackingVM: TrackingViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: trackingVM.getIcon(for: bid))
                .resizable()
                .frame(width: 32, height: 32)
                .padding(6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(stats.appName.isEmpty ? "Unknown App" : stats.appName)
                    .font(.system(size: 13, weight: .bold))
                Text(bid)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatTime(stats.totalLifetimeTime))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text("LIFETIME")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }
}
