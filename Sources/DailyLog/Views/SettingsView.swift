import SwiftUI

struct SettingsView: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @Binding var isPresented: Bool
    
    @State private var showingResetConfirm = false
    @State private var showingImportView = false
    @State private var exportStatus = "Copy data to clipboard as JSON"
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if showingImportView {
                    ImportView(trackingVM: trackingVM, isPresented: $showingImportView)
                } else {
                    // Main Settings Header
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
                        
                        Text("Settings")
                            .font(.system(size: 14, weight: .bold))
                        
                        Spacer()
                        
                        Text("Back").font(.system(size: 13)).opacity(0)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    
                    Divider().opacity(0.5)
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Data Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("DATA MANAGEMENT")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .tracking(1)
                                
                                VStack(spacing: 1) {
                                    // Export
                                    Button(action: exportData) {
                                        SettingRow(title: "Export Data", subtitle: exportStatus, icon: "square.and.arrow.up", color: .blue)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider().opacity(0.2).padding(.leading, 44)
                                    
                                    // Import
                                    Button(action: { 
                                        withAnimation { showingImportView = true }
                                    }) {
                                        SettingRow(title: "Import Data", subtitle: "Load data from JSON string", icon: "square.and.arrow.down", color: .orange)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider().opacity(0.2).padding(.leading, 44)
                                    
                                    // Reset
                                    Button(action: { 
                                        withAnimation { showingResetConfirm = true }
                                    }) {
                                        SettingRow(title: "Reset All Data", subtitle: "Permanently delete everything", icon: "trash.fill", color: .red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                )
                            }
                            
                            // About Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ABOUT")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .tracking(1)
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("DailyLog for macOS")
                                            .font(.system(size: 13, weight: .bold))
                                        Text("Version 1.0.0")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            // Inline Confirmation Overlay
            if showingResetConfirm {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture { withAnimation { showingResetConfirm = false } }
                    
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                        
                        Text("Reset All Data?")
                            .font(.headline)
                        
                        Text("This action cannot be undone. You will lose your levels, coins, and history.")
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                trackingVM.clearAllData()
                                withAnimation { showingResetConfirm = false }
                            }) {
                                Text("Reset Everything")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.red)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation { showingResetConfirm = false }
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 20)
                    .frame(width: 260)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                }
            }
        }
    }
    
    private func exportData() {
        if let json = trackingVM.exportAsJSON() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(json, forType: .string)
            
            withAnimation {
                exportStatus = "✅ Copied to clipboard!"
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    exportStatus = "Copy data to clipboard as JSON"
                }
            }
        }
    }
}

struct SettingRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

struct ImportView: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @Binding var isPresented: Bool
    @State private var jsonText = ""
    @State private var errorMsg = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { 
                    withAnimation { isPresented = false }
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
                
                Text("Import Data")
                    .font(.system(size: 14, weight: .bold))
                
                Spacer()
                
                Text("Back").font(.system(size: 13)).opacity(0)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider().opacity(0.5)
            
            ScrollView {
                VStack(spacing: 16) {
                    Text("Paste your exported JSON data below to restore your progress.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    TextEditor(text: $jsonText)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(height: 180)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    Button(action: {
                        if trackingVM.importFromJSON(jsonText) {
                            withAnimation { isPresented = false }
                        } else {
                            errorMsg = "❌ Invalid JSON. Please check and try again."
                        }
                    }) {
                        Text("Restore Data")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    .disabled(jsonText.isEmpty)
                }
                .padding()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
