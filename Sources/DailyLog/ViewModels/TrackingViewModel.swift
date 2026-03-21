import AppKit
import Combine
import Foundation

class TrackingViewModel: ObservableObject {
    @Published var gameState: GameState = GameState()
    @Published var currentAppName: String = "Monitoring..."
    @Published var isProductiveAppActive: Bool = false
    var systemMonitor = SystemMonitorManager()
    
    // Icon Cache
    @Published var iconCache: [String: NSImage] = [:]
    
    var sortedProductiveApps: [ProductiveApp] {
        gameState.productiveApps.sorted {
            let time1 = gameState.allTimeStats[$0.bundleId]?.totalTimeToday ?? 0
            let time2 = gameState.allTimeStats[$1.bundleId]?.totalTimeToday ?? 0
            return time1 > time2
        }
    }
    
    private var pendingExpSeconds: TimeInterval = 0
    private var timer: Timer?
    private var lastTick: Date = Date()
    private var currentDayString: String = ""
    
    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        currentDayString = formatter.string(from: Date())
        
        loadState()
        startGlobalTracking()
        
        // Initial cache population
        refreshIconCache()
    }
    
    func startGlobalTracking() {
        timer?.invalidate()
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
            if todayString != self.currentDayString {
                self.currentDayString = todayString
                for bid in self.gameState.allTimeStats.keys {
                    self.gameState.allTimeStats[bid]?.totalTimeToday = 0
                }
                self.saveState()
            }

            self.pendingExpSeconds += delta
            if self.pendingExpSeconds >= 60 {
                let mins = Int(self.pendingExpSeconds / 60)
                self.gameState.addExp(mins)
                self.pendingExpSeconds -= TimeInterval(mins * 60)
                self.saveState()
            }
            
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontmost.bundleIdentifier {
                
                self.currentAppName = frontmost.localizedName ?? "Unknown"
                
                if let productiveApp = self.gameState.productiveApps.first(where: { $0.bundleId == bundleId }) {
                    self.isProductiveAppActive = true
                    
                    var stats = self.gameState.allTimeStats[bundleId] ?? AppStats()
                    stats.appName = productiveApp.appName
                    stats.totalTimeToday += delta
                    stats.totalLifetimeTime += delta
                    self.gameState.allTimeStats[bundleId] = stats
                    
                    // Cache icon if missing, but DO NOT trigger redraw here
                    if self.iconCache[bundleId] == nil {
                        self.silentCacheIcon(for: bundleId)
                    }
                } else {
                    self.isProductiveAppActive = false
                }
            }
        }
    }
    
    // Non-triggering icon fetch for View use
    func getIcon(for bundleId: String) -> NSImage {
        return iconCache[bundleId] ?? NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
    }
    
    private func silentCacheIcon(for bundleId: String) {
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
        }
        self.iconCache[bundleId] = icon
    }
    
    func addProductiveApp(bundleId: String, name: String) {
        if !gameState.productiveApps.contains(where: { $0.bundleId == bundleId }) {
            gameState.productiveApps.append(ProductiveApp(bundleId: bundleId, appName: name))
            silentCacheIcon(for: bundleId)
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
    
    func refreshIconCache() {
        for app in gameState.productiveApps {
            silentCacheIcon(for: app.bundleId)
        }
        for bid in gameState.allTimeStats.keys {
            silentCacheIcon(for: bid)
        }
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
                
                let icon = app.icon ?? self.getIcon(for: bid)
                return AppInfo(id: bid, name: name, icon: icon)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func clearAllData() {
        gameState = GameState()
        iconCache.removeAll()
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
    
    func importFromJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return "Encoding error" }
        do {
            let newState = try JSONDecoder().decode(GameState.self, from: data)
            self.gameState = newState
            self.refreshIconCache()
            self.saveState()
            return nil
        } catch {
            return "JSON Error: \(error.localizedDescription)"
        }
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
