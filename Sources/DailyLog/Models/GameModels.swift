import Foundation

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

struct GameState: Codable {
    var totalLifetimeExp: Int = 0 // 1 EXP = 1 Minute
    var coins: Int = 0
    var productiveApps: [ProductiveApp] = []
    var allTimeStats: [String: AppStats] = [:]
    
    // Calculated Progress Strings
    var progressTimeText: String {
        let current = Double(exp)
        let total = Double(requiredExpForNextLevel)
        return formatProgress(current: current, total: total)
    }
    
    var totalLifetimeTimeText: String {
        return formatSingleValue(Double(totalLifetimeExp))
    }
    
    // Computed Properties for UI
    var level: Int { calculateLevelAndProgress().level }
    var exp: Int { calculateLevelAndProgress().exp }
    var requiredExpForNextLevel: Int { calculateLevelAndProgress().required }
    
    private func calculateLevelAndProgress() -> (level: Int, exp: Int, required: Int) {
        var remainingExp = totalLifetimeExp
        var currentLevel = 1
        var req = Int(60 * pow(Double(currentLevel), 1.5))
        
        while remainingExp >= req {
            remainingExp -= req
            currentLevel += 1
            req = Int(60 * pow(Double(currentLevel), 1.5))
        }
        return (currentLevel, remainingExp, req)
    }
    
    // Helper to format 0.1y/1y style
    private func formatProgress(current: Double, total: Double) -> String {
        let divider: Double
        let unit: String
        
        if total >= 525600 { unit = "y"; divider = 525600 }      // 1 Year
        else if total >= 43200 { unit = "mo"; divider = 43200 } // 1 Month
        else if total >= 1440 { unit = "d"; divider = 1440 }    // 1 Day
        else if total >= 60 { unit = "h"; divider = 60 }        // 1 Hour
        else { unit = "m"; divider = 1 }                        // 1 Minute
        
        let curVal = current / divider
        let totVal = total / divider
        
        let curStr = formatNumber(curVal)
        let totStr = formatNumber(totVal)
        
        return "\(curStr)\(unit)/\(totStr)\(unit)"
    }
    
    private func formatSingleValue(_ value: Double) -> String {
        if value >= 525600 { return "\(formatNumber(value / 525600))y" }
        if value >= 43200 { return "\(formatNumber(value / 43200))mo" }
        if value >= 1440 { return "\(formatNumber(value / 1440))d" }
        if value >= 60 { return "\(formatNumber(value / 60))h" }
        return "\(Int(value))m"
    }
    
    private func formatNumber(_ num: Double) -> String {
        if num.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", num)
        } else {
            return String(format: "%.1f", num)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case totalLifetimeExp, coins, productiveApps, allTimeStats
    }
    
    init() {
        self.totalLifetimeExp = 0
        self.coins = 0
        self.productiveApps = []
        self.allTimeStats = [:]
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalLifetimeExp = try container.decodeIfPresent(Int.self, forKey: .totalLifetimeExp) ?? 0
        self.coins = try container.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        self.productiveApps = try container.decodeIfPresent([ProductiveApp].self, forKey: .productiveApps) ?? []
        self.allTimeStats = try container.decodeIfPresent([String: AppStats].self, forKey: .allTimeStats) ?? [:]
    }
    
    mutating func addExp(_ amount: Int) {
        totalLifetimeExp += amount
    }
}
