import SwiftUI
import HardwareKit

struct SettingsView: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @Binding var isPresented: Bool

    @State private var showingResetConfirm = false
    @State private var showingImportView = false
    @State private var exportStatus = "Copy data to clipboard as JSON"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

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

                    ScrollView {
                        GlassGroup(spacing: 16) {
                            VStack(spacing: 20) {
                                appearanceSection
                                menuBarSection

                                if !trackingVM.systemMonitor.stats.fans.isEmpty {
                                    FanControlSection(trackingVM: trackingVM, monitor: trackingVM.systemMonitor, controller: trackingVM.fanController)
                                }

                                processAlertsSection
                                dataSection
                                aboutSection
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .popoverBackground()

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

                        Text("This action cannot be undone. You will lose your levels and history.")
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
                    .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(radius: 20)
                }
            }
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        SettingsGroup(title: "APPEARANCE") {
            ToggleRow(title: "Show Level & EXP", icon: "p.circle.fill", color: .blue, isOn: $trackingVM.gameState.uiSettings.showHeader)
            Divider().opacity(0.2).padding(.leading, 44)
            ToggleRow(title: "Show System Performance", icon: "cpu.fill", color: .purple, isOn: $trackingVM.gameState.uiSettings.showSystemMonitor)
            Divider().opacity(0.2).padding(.leading, 44)
            ToggleRow(title: "Show Productive Apps", icon: "app.badge.fill", color: .orange, isOn: $trackingVM.gameState.uiSettings.showProductiveApps)
            Divider().opacity(0.2).padding(.leading, 44)
            ToggleRow(title: "Show Top Processes", icon: "list.bullet.rectangle.fill", color: .pink, isOn: $trackingVM.gameState.uiSettings.showProcessMonitor)
            Divider().opacity(0.2).padding(.leading, 44)
            ToggleRow(title: "Show History Button", icon: "chart.bar.fill", color: .green, isOn: $trackingVM.gameState.uiSettings.showHistoryButton)
            if #available(macOS 26.0, *) {
                Divider().opacity(0.2).padding(.leading, 44)
                ToggleRow(title: "Liquid Glass Cards", subtitle: "Richer look, but uses more GPU", icon: "sparkles", color: .cyan, isOn: $trackingVM.gameState.uiSettings.liquidGlassCards)
            }
        }
    }

    private var menuBarSection: some View {
        let hasFans = !trackingVM.systemMonitor.stats.fans.isEmpty
        let available = MenuBarMetric.allCases.filter { hasFans || $0 != .fan }
        return SettingsGroup(title: "MENU BAR DISPLAY") {
            PickerRow(title: "Leading Info", selection: $trackingVM.gameState.uiSettings.menuBarLeading, options: available)
            Divider().opacity(0.2).padding(.leading, 12)
            ToggleRow(title: "Show Second Metric", icon: "rectangle.split.2x1.fill", color: .indigo, isOn: $trackingVM.gameState.uiSettings.showTrailingMetric)
            if trackingVM.gameState.uiSettings.showTrailingMetric {
                Divider().opacity(0.2).padding(.leading, 12)
                PickerRow(title: "Trailing Info", selection: $trackingVM.gameState.uiSettings.menuBarTrailing, options: available)
            }
            Divider().opacity(0.2).padding(.leading, 12)
            MenuBarStylePickerRow(title: "Display Style", selection: $trackingVM.gameState.uiSettings.menuBarStyle)
            Divider().opacity(0.2).padding(.leading, 44)
            ToggleRow(title: "Colored Graphs", icon: "paintpalette.fill", color: .teal, isOn: $trackingVM.gameState.uiSettings.menuBarColored)
        }
    }

    private var processAlertsSection: some View {
        SettingsGroup(title: "PROCESS ALERTS") {
            SliderSettingRow(title: "CPU Alert Threshold", icon: "cpu.fill", color: .pink, value: $trackingVM.gameState.uiSettings.cpuAlertThreshold, range: 10...100, step: 5, unit: "%")
            Divider().opacity(0.2).padding(.leading, 12)
            SliderSettingRow(title: "RAM Alert Threshold", icon: "memorychip.fill", color: .orange, value: $trackingVM.gameState.uiSettings.ramAlertThreshold, range: 100...4000, step: 100, unit: "MB")
        }
    }

    private var dataSection: some View {
        SettingsGroup(title: "DATA MANAGEMENT", spacing: 1) {
            Button(action: exportData) {
                SettingRow(title: "Export Data", subtitle: exportStatus, icon: "square.and.arrow.up", color: .blue)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.2).padding(.leading, 44)

            Button(action: {
                withAnimation { showingImportView = true }
            }) {
                SettingRow(title: "Import Data", subtitle: "Load data from JSON string", icon: "square.and.arrow.down", color: .orange)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.2).padding(.leading, 44)

            Button(action: {
                withAnimation { showingResetConfirm = true }
            }) {
                SettingRow(title: "Reset All Data", subtitle: "Permanently delete everything", icon: "trash.fill", color: .red)
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        SettingsGroup(title: "ABOUT") {
            HStack(spacing: 12) {
                AppLogoView(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DailyLog for macOS")
                        .font(.system(size: 13, weight: .bold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
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

// MARK: - Fan control

struct FanControlSection: View {
    @ObservedObject var trackingVM: TrackingViewModel
    @ObservedObject var monitor: SystemMonitorManager
    @ObservedObject var controller: FanController

    private var fans: [FanReading] { monitor.stats.fans }
    private var mode: FanControlMode { trackingVM.gameState.uiSettings.fanControlMode }
    private var fraction: Double { trackingVM.gameState.uiSettings.fanManualFraction }

    private var modeBinding: Binding<FanControlMode> {
        Binding(
            get: { mode },
            set: { trackingVM.setFanMode($0) }
        )
    }

    private var fractionBinding: Binding<Double> {
        Binding(
            get: { fraction },
            set: { trackingVM.gameState.uiSettings.fanManualFraction = $0 }
        )
    }

    var body: some View {
        SettingsGroup(title: "FAN CONTROL") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "fan.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Palette.fan)
                        .cornerRadius(6)
                    Text("Fan Speed")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: modeBinding) {
                        ForEach(FanControlMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                    .disabled(controller.isBusy)
                }

                if mode == .manual {
                    manualControls
                }

                statusLine

                Text("Manual mode asks for your administrator password once per launch. macOS takes control back if the chip gets too hot, and whenever you quit DailyLog.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Target speed")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(targetSummary)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Palette.fan)
            }

            Slider(value: fractionBinding, in: 0...1, onEditingChanged: { editing in
                // Apply on release, not on every drag tick: each apply is a round trip to the root helper.
                if !editing { controller.apply(mode: .manual, fraction: fraction) }
            })
            .tint(Palette.fan)
            .disabled(controller.isBusy)

            HStack {
                Text("Min \(rangeText(\.minRPM))")
                Spacer()
                Text("Max \(rangeText(\.maxRPM))")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)

            ForEach(fans) { fan in
                HStack {
                    Text("Fan \(fan.index + 1)")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("now \(Format.rpm(fan.currentRPM)) · target \(Format.rpm(FanCurve.rpm(forFraction: fraction, min: fan.minRPM, max: fan.maxRPM))) RPM")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if controller.isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(controller.status == .authorizing ? "Waiting for administrator approval…" : "Applying…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        } else if let error = controller.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if mode == .manual && controller.appliedMode == .manual {
            Label("Manual speed is active.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Palette.download)
        } else {
            Text("macOS manages fan speed automatically.")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var targetSummary: String {
        let rpms = fans.map { FanCurve.rpm(forFraction: fraction, min: $0.minRPM, max: $0.maxRPM) }
        guard !rpms.isEmpty else { return "" }
        let unique = Array(Set(rpms)).sorted()
        return unique.map(Format.rpm).joined(separator: " / ") + " RPM"
    }

    private func rangeText(_ keyPath: KeyPath<FanReading, Double>) -> String {
        guard let first = fans.first else { return "" }
        return "\(Format.rpm(first[keyPath: keyPath])) RPM"
    }
}

// MARK: - Building blocks

struct SettingsGroup<Content: View>: View {
    let title: String
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1)
                .padding(.leading, 6)

            VStack(spacing: spacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18)
        }
    }
}

struct PickerRow: View {
    let title: String
    @Binding var selection: MenuBarMetric
    var options: [MenuBarMetric] = MenuBarMetric.allCases

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct MenuBarStylePickerRow: View {
    let title: String
    @Binding var selection: MenuBarStyle

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(MenuBarStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SliderSettingRow: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .cornerRadius(6)

                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text("\(Int(value))\(unit)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .tint(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                        .scrollContentBackground(.hidden)
                        .glassCard(cornerRadius: 14)

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    Button(action: {
                        if let error = trackingVM.importFromJSON(jsonText) {
                            errorMsg = "❌ " + error
                        } else {
                            withAnimation { isPresented = false }
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
        .popoverBackground()
    }
}
