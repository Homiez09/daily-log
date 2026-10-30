import Foundation

enum MenuBarMetric: String, Codable, CaseIterable {
    case cpu = "CPU"
    case ram = "RAM"
    case gpu = "GPU"
    case storage = "Disk"
    case temp = "Temp"
    case network = "Net"
    case fan = "Fan"
}

enum MenuBarStyle: String, Codable, CaseIterable {
    case solid = "Bar"
    case line = "Line"
    case wave = "Wave"
}

enum FanControlMode: String, Codable, CaseIterable {
    case auto = "Auto"
    case manual = "Manual"
}

struct ProductiveApp: Identifiable, Codable, Equatable {
    var id: String { bundleId }
    let bundleId: String
    let appName: String
}

struct AppStats: Codable {
    var appName: String = ""
    var totalTimeToday: TimeInterval = 0
    var totalLifetimeTime: TimeInterval = 0
}

struct UISettings: Codable {
    var showHeader: Bool = true
    var showSystemMonitor: Bool = true
    var showProductiveApps: Bool = true
    var showHistoryButton: Bool = true
    var showProcessMonitor: Bool = true

    // Menu Bar Config
    var menuBarLeading: MenuBarMetric = .cpu
    var menuBarTrailing: MenuBarMetric = .ram
    var showTrailingMetric: Bool = false
    var menuBarStyle: MenuBarStyle = .solid
    /// false = monochrome template image that adapts to the menu bar; true = coloured graphs.
    var menuBarColored: Bool = false

    /// Real Liquid Glass cards (macOS 26+). Off by default: each glass layer is extra WindowServer GPU
    /// work, which adds up fast over a live video wallpaper.
    var liquidGlassCards: Bool = false

    // Fan control. `fanManualFraction` is a 0...1 position inside each fan's own min...max RPM range.
    var fanControlMode: FanControlMode = .auto
    var fanManualFraction: Double = 0.5

    // Per-process alert thresholds
    var cpuAlertThreshold: Double = 50.0   // percent
    var ramAlertThreshold: Double = 500.0  // MB

    init() {}

    enum CodingKeys: String, CodingKey {
        case showHeader, showSystemMonitor, showProductiveApps, showHistoryButton, showProcessMonitor
        case menuBarLeading, menuBarTrailing, menuBarStyle, cpuAlertThreshold, ramAlertThreshold
        case showTrailingMetric, menuBarColored, fanControlMode, fanManualFraction, liquidGlassCards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHeader = try container.decodeIfPresent(Bool.self, forKey: .showHeader) ?? true
        showSystemMonitor = try container.decodeIfPresent(Bool.self, forKey: .showSystemMonitor) ?? true
        showProductiveApps = try container.decodeIfPresent(Bool.self, forKey: .showProductiveApps) ?? true
        showHistoryButton = try container.decodeIfPresent(Bool.self, forKey: .showHistoryButton) ?? true
        showProcessMonitor = try container.decodeIfPresent(Bool.self, forKey: .showProcessMonitor) ?? true
        menuBarLeading = try container.decodeIfPresent(MenuBarMetric.self, forKey: .menuBarLeading) ?? .cpu
        menuBarTrailing = try container.decodeIfPresent(MenuBarMetric.self, forKey: .menuBarTrailing) ?? .ram
        menuBarStyle = try container.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? .solid
        cpuAlertThreshold = try container.decodeIfPresent(Double.self, forKey: .cpuAlertThreshold) ?? 50.0
        ramAlertThreshold = try container.decodeIfPresent(Double.self, forKey: .ramAlertThreshold) ?? 500.0
        showTrailingMetric = try container.decodeIfPresent(Bool.self, forKey: .showTrailingMetric) ?? false
        menuBarColored = try container.decodeIfPresent(Bool.self, forKey: .menuBarColored) ?? false
        liquidGlassCards = try container.decodeIfPresent(Bool.self, forKey: .liquidGlassCards) ?? false
        fanControlMode = try container.decodeIfPresent(FanControlMode.self, forKey: .fanControlMode) ?? .auto
        let storedFraction = try container.decodeIfPresent(Double.self, forKey: .fanManualFraction) ?? 0.5
        fanManualFraction = storedFraction.isFinite ? min(max(storedFraction, 0), 1) : 0.5
    }
}

struct GameState: Codable {
    var totalLifetimeExp: Int = 0
    var productiveApps: [ProductiveApp] = []
    var allTimeStats: [String: AppStats] = [:]
    var uiSettings: UISettings = UISettings()
    
    var level: Int { calculateLevelAndProgress().level }
    var exp: Int { calculateLevelAndProgress().exp }
    var requiredExpForNextLevel: Int { calculateLevelAndProgress().required }
    
    var progressTimeText: String {
        let current = Double(exp)
        let total = Double(requiredExpForNextLevel)
        return formatProgress(current: current, total: total)
    }
    
    var totalLifetimeTimeText: String {
        return formatSingleValue(Double(totalLifetimeExp))
    }
    
    private func calculateLevelAndProgress() -> (level: Int, exp: Int, required: Int) {
        let C: Double = 60.0
        let totalExp = Double(totalLifetimeExp)
        
        // Current lvl
        let currentLevel = Int(floor(sqrt(totalExp / C))) + 1
        
        // Total Exp for current lvl and next lvl
        let totalExpForCurrentLevel = Int(C * pow(Double(currentLevel - 1), 2))
        let totalExpForNextLevel = Int(C * pow(Double(currentLevel), 2))
        
        // return currentLevel, remainingExp, reqExp
        let remainingExp = totalLifetimeExp - totalExpForCurrentLevel
        let reqExp = totalExpForNextLevel - totalExpForCurrentLevel
        
        return (currentLevel, remainingExp, reqExp)
    }
    
    private func formatProgress(current: Double, total: Double) -> String {
        let divider: Double; let unit: String
        if total >= 525600 { unit = "y"; divider = 525600 }
        else if total >= 43200 { unit = "mo"; divider = 43200 }
        else if total >= 1440 { unit = "d"; divider = 1440 }
        else if total >= 60 { unit = "h"; divider = 60 }
        else { unit = "m"; divider = 1 }
        let curVal = floor(current / divider * 10) / 10.0
        let totVal = floor(total / divider * 10) / 10.0
        return "\(formatNumber(curVal))\(unit)/\(formatNumber(totVal))\(unit)"
    }
    
    private func formatSingleValue(_ value: Double) -> String {
        if value >= 525600 { return "\(formatNumber(floor(value / 525600 * 10) / 10.0))y" }
        if value >= 43200 { return "\(formatNumber(floor(value / 43200 * 10) / 10.0))mo" }
        if value >= 1440 { return "\(formatNumber(floor(value / 1440 * 10) / 10.0))d" }
        if value >= 60 { return "\(formatNumber(floor(value / 60 * 10) / 10.0))h" }
        return "\(Int(value))m"
    }
    
    
    
    private func formatNumber(_ num: Double) -> String {
        return num.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", num) : String(format: "%.1f", num)
    }
    
    enum CodingKeys: String, CodingKey {
        case totalLifetimeExp, productiveApps, allTimeStats, uiSettings
    }
    
    init() {
        self.totalLifetimeExp = 0
        self.productiveApps = []
        self.allTimeStats = [:]
        self.uiSettings = UISettings()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Ensure totalLifetimeExp is decoded correctly, falling back only if strictly necessary but preferring to throw if key is missing to warn identifying missing data
        self.totalLifetimeExp = try container.decode(Int.self, forKey: .totalLifetimeExp)
        self.productiveApps = try container.decodeIfPresent([ProductiveApp].self, forKey: .productiveApps) ?? []
        self.allTimeStats = try container.decodeIfPresent([String: AppStats].self, forKey: .allTimeStats) ?? [:]
        self.uiSettings = try container.decodeIfPresent(UISettings.self, forKey: .uiSettings) ?? UISettings()
    }
    
    mutating func addExp(_ amount: Int) {
        totalLifetimeExp += amount
    }
}
