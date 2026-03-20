import AppKit
import Combine
import Foundation

class TrackingViewModel: ObservableObject {
    @Published var gameState: GameState = GameState()
    @Published var currentAppName: String = "Monitoring..."
    @Published var isProductiveAppActive: Bool = false
    var systemMonitor = SystemMonitorManager()
    
    // Sort based on today's time stored in allTimeStats
    var sortedProductiveApps: [ProductiveApp] {
        gameState.productiveApps.sorted {
            let time1 = gameState.allTimeStats[$0.bundleId]?.totalTimeToday ?? 0
            let time2 = gameState.allTimeStats[$1.bundleId]?.totalTimeToday ?? 0
            return time1 > time2
        }
    }
    
    private var pendingExpSeconds: TimeInterval = 0
    private var pendingCoinSeconds: TimeInterval = 0
    private var timer: Timer?
    private var lastTick: Date = Date()
    private var currentDayString: String = ""
    private var lastSaveTime: Date = Date()
    
    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        currentDayString = formatter.string(from: Date())
        
        loadState()
        startGlobalTracking()
    }
    
    func startGlobalTracking() {
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: now)
        
        DispatchQueue.main.async {
            // Day change reset
            if todayString != self.currentDayString {
                self.currentDayString = todayString
                for bid in self.gameState.allTimeStats.keys {
                    self.gameState.allTimeStats[bid]?.totalTimeToday = 0
                }
                self.saveState()
            }

            // 1. Online EXP
            self.pendingExpSeconds += delta
            if self.pendingExpSeconds >= 60 {
                let mins = Int(self.pendingExpSeconds / 60)
                self.gameState.addExp(mins)
                self.pendingExpSeconds -= TimeInterval(mins * 60)
                self.saveState()
            }
            
            // 2. Productive Time Tracking
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontmost.bundleIdentifier {
                
                self.currentAppName = frontmost.localizedName ?? "Unknown"
                
                // Track time if it's in the PRODUCTIVE list
                if let productiveApp = self.gameState.productiveApps.first(where: { $0.bundleId == bundleId }) {
                    self.isProductiveAppActive = true
                    
                    // Update the stats vault
                    var stats = self.gameState.allTimeStats[bundleId] ?? AppStats()
                    stats.appName = productiveApp.appName
                    stats.totalTimeToday += delta
                    stats.totalLifetimeTime += delta
                    self.gameState.allTimeStats[bundleId] = stats
                } else {
                    self.isProductiveAppActive = false
                }
            }
        }
    }
    
    func addProductiveApp(bundleId: String, name: String) {
        if !gameState.productiveApps.contains(where: { $0.bundleId == bundleId }) {
            gameState.productiveApps.append(ProductiveApp(bundleId: bundleId, appName: name))
            saveState()
        }
    }
    
    func removeProductiveApp(bundleId: String) {
        gameState.productiveApps.removeAll { $0.bundleId == bundleId }
        saveState()
    }
    
    func getTimeToday(for bundleId: String) -> TimeInterval {
        return gameState.allTimeStats[bundleId]?.totalTimeToday ?? 0
    }
    
    struct AppInfo: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
    }
    
    func getAddableApps() -> [AppInfo] {
        let addedBundleIds = Set(gameState.productiveApps.map { $0.bundleId })
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { (app: NSRunningApplication) -> AppInfo? in
                guard let bid = app.bundleIdentifier,
                      let name = app.localizedName,
                      !addedBundleIds.contains(bid) else { return nil }
                
                let icon: NSImage
                if let appIcon = app.icon {
                    icon = appIcon
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                } else {
                    icon = NSImage(named: NSImage.applicationIconName) ?? NSImage()
                }
                
                return AppInfo(id: bid, name: name, icon: icon)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    // Data Management
    func clearAllData() {
        gameState = GameState()
        saveState()
        UserDefaults.standard.removeObject(forKey: "GameState")
        UserDefaults.standard.removeObject(forKey: "CurrentDay")
    }
    
    func exportAsJSON() -> String? {
        if let data = try? JSONEncoder().encode(gameState) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func importFromJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        if let newState = try? JSONDecoder().decode(GameState.self, from: data) {
            self.gameState = newState
            self.saveState()
            return true
        }
        return false
    }
    
    private func saveState() {
        if let data = try? JSONEncoder().encode(gameState) {
            UserDefaults.standard.set(data, forKey: "GameState")
        }
        UserDefaults.standard.set(currentDayString, forKey: "CurrentDay")
    }
    
    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: "GameState"),
           let state = try? JSONDecoder().decode(GameState.self, from: data) {
            self.gameState = state
        }
        if let day = UserDefaults.standard.string(forKey: "CurrentDay") {
            self.currentDayString = day
        }
    }
    
    func resetProgressForTimer(delta: TimeInterval) {}
    func resetSession() {}
}
