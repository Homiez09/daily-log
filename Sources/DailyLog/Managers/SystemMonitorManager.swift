import Foundation
import IOKit
import AppKit
import Darwin
import HardwareKit

enum CPUCoreType {
    case efficiency
    case performance
    case unknown
}

enum MemoryPressure {
    case normal, warning, critical

    /// `kern.memorystatus_vm_pressure_level`: 1 = normal, 2 = warn, 4 = critical.
    init(sysctlLevel: Int) {
        switch sysctlLevel {
        case 4...: self = .critical
        case 2...: self = .warning
        default: self = .normal
        }
    }
}

struct ProcessStats: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    var cpuUsage: Double = 0
    var ramUsageMB: Double = 0
}

struct SystemStats {
    var cpuUsage: Double = 0
    var perCoreUsage: [Double] = []
    var gpuUsage: Double = 0

    // Memory, in GiB. `ramUsed` follows Activity Monitor's "Memory Used" = App + Wired + Compressed.
    var ramUsed: Double = 0
    var ramTotal: Double = 0
    var ramApp: Double = 0
    var ramWired: Double = 0
    var ramCompressed: Double = 0
    var ramCached: Double = 0
    var memoryPressure: MemoryPressure = .normal

    var diskUsed: Double = 0
    var diskTotal: Double = 0

    // Bytes per second.
    var networkDownload: Double = 0
    var networkUpload: Double = 0

    // nil means the Mac exposes no readable sensor; the UI shows "—" instead of inventing a number.
    var temperature: Double?
    var temperatureMax: Double?
    var ssdTemperature: Double?
    var batteryTemperature: Double?

    var fans: [FanReading] = []
    var topProcesses: [ProcessStats] = []
}

class SystemMonitorManager: ObservableObject {
    @Published var stats = SystemStats()
    @Published var coreTypes: [CPUCoreType] = []
    @Published var metricHistory: [MenuBarMetric: [Double]] = [:]

    /// Evaluated once: it never changes at runtime and the dashboard re-renders every tick.
    let cpuName: String

    private let historyLimit = 40
    private var timer: Timer?
    private var previousProcessorInfo: processor_info_array_t?
    private var previousProcessorInfoCount: mach_msg_type_number_t = 0
    private var previousProcessorCount: mach_msg_type_number_t = 0
    private var lastNetData: (in: UInt64, out: UInt64, time: Date)?
    private var previousProcessCPUTime: [pid_t: Double] = [:]
    private var previousProcessSampleTime: Date = Date()
    private let smc: SMCConnection? = try? SMCConnection()
    private let thermalSensors: ThermalSensors? = ThermalSensors()

    init() {
        cpuName = SystemMonitorManager.readCPUName()
        self.stats.ramTotal = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        detectCoreTypes()
        refreshStats()
        startMonitoring()
        // CPU/network are rate metrics that need two samples; take the second one soon so the
        // popover does not show zeros for the first two seconds after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshStats() }
    }

    deinit {
        stopMonitoring()
        if let prev = previousProcessorInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: Int(bitPattern: prev)), vm_size_t(previousProcessorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Core layout

    /// host_processor_info reports the least performant cluster first, so walk the perf levels
    /// from the highest index (efficiency) down to 0 (performance).
    private func detectCoreTypes() {
        var types: [CPUCoreType] = []
        let levels = getSysctlInt("hw.nperflevels")
        if levels > 0 {
            for level in stride(from: levels - 1, through: 0, by: -1) {
                let count = getSysctlInt("hw.perflevel\(level).logicalcpu")
                let name = getSysctlString("hw.perflevel\(level).name").lowercased()
                let type: CPUCoreType = name.contains("efficiency") ? .efficiency : .performance
                types.append(contentsOf: Array(repeating: type, count: count))
            }
        }
        if types.isEmpty {
            types = Array(repeating: .unknown, count: ProcessInfo.processInfo.activeProcessorCount)
        }
        self.coreTypes = types
    }

    private func getSysctlInt(_ name: String) -> Int {
        var size = MemoryLayout<Int>.size
        var value = Int()
        if sysctlbyname(name, &value, &size, nil, 0) == 0 { return value }
        return 0
    }

    private func getSysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    // MARK: Polling

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStats()
        }
        // Ensure timer doesn't stop when menu is open
        RunLoop.current.add(timer!, forMode: .common)
    }

    func refreshStats() {
        var newStats = self.stats

        updateCPU(into: &newStats)
        updateRAM(into: &newStats)
        updateGPU(into: &newStats)
        updateStorage(into: &newStats)
        updateNetwork(into: &newStats)
        updateTemperature(into: &newStats)
        updateFans(into: &newStats)
        updateProcesses(into: &newStats)

        DispatchQueue.main.async {
            self.stats = newStats
            self.updateMetricHistory(from: newStats)
        }
    }

    func progressValue(for metric: MenuBarMetric, stats: SystemStats) -> Double {
        switch metric {
        case .cpu: return safeProgress(stats.cpuUsage / 100)
        case .gpu: return safeProgress(stats.gpuUsage / 100)
        case .ram: return stats.ramTotal > 0 ? safeProgress(stats.ramUsed / stats.ramTotal) : 0
        case .storage: return stats.diskTotal > 0 ? safeProgress(stats.diskUsed / stats.diskTotal) : 0
        case .temp: return safeProgress((stats.temperature ?? 0) / 110)
        case .network: return safeProgress(min((stats.networkDownload + stats.networkUpload) / (10 * 1024 * 1024), 1.0))
        case .fan:
            guard !stats.fans.isEmpty else { return 0 }
            return safeProgress(stats.fans.map(\.fraction).reduce(0, +) / Double(stats.fans.count))
        }
    }

    private func safeProgress(_ value: Double) -> Double {
        if value.isNaN || value.isInfinite { return 0 }
        return min(max(value, 0), 1)
    }

    private func updateMetricHistory(from stats: SystemStats) {
        for metric in MenuBarMetric.allCases {
            var samples = metricHistory[metric] ?? []
            samples.append(progressValue(for: metric, stats: stats))
            if samples.count > historyLimit {
                samples.removeFirst(samples.count - historyLimit)
            }
            metricHistory[metric] = samples
        }
    }

    // MARK: CPU

    private func updateCPU(into stats: inout SystemStats) {
        var processorCount: mach_msg_type_number_t = 0
        var processorInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &infoCount)
        guard result == KERN_SUCCESS, let info = processorInfo else { return }

        if let prev = previousProcessorInfo, previousProcessorCount == processorCount {
            var coreUsages: [Double] = []
            var activeTicks: UInt64 = 0
            var totalTicks: UInt64 = 0

            for i in 0..<Int(processorCount) {
                let index = i * Int(CPU_STATE_MAX)

                // Tick counters are 32-bit and wrap, so subtract with wrapping semantics.
                let user = UInt64(UInt32(bitPattern: info[index + Int(CPU_STATE_USER)]) &- UInt32(bitPattern: prev[index + Int(CPU_STATE_USER)]))
                let system = UInt64(UInt32(bitPattern: info[index + Int(CPU_STATE_SYSTEM)]) &- UInt32(bitPattern: prev[index + Int(CPU_STATE_SYSTEM)]))
                let idle = UInt64(UInt32(bitPattern: info[index + Int(CPU_STATE_IDLE)]) &- UInt32(bitPattern: prev[index + Int(CPU_STATE_IDLE)]))
                let nice = UInt64(UInt32(bitPattern: info[index + Int(CPU_STATE_NICE)]) &- UInt32(bitPattern: prev[index + Int(CPU_STATE_NICE)]))

                let active = user + system + nice
                let total = active + idle
                // Always append, even for an idle core, so indices stay aligned with `coreTypes`.
                coreUsages.append(total > 0 ? Double(active) / Double(total) * 100.0 : 0)
                activeTicks += active
                totalTicks += total
            }

            stats.perCoreUsage = coreUsages
            stats.cpuUsage = totalTicks > 0 ? Double(activeTicks) / Double(totalTicks) * 100.0 : 0
        }

        if let prev = previousProcessorInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: Int(bitPattern: prev)), vm_size_t(previousProcessorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        previousProcessorInfo = info
        previousProcessorInfoCount = infoCount
        previousProcessorCount = processorCount
    }

    // MARK: Memory

    private func updateRAM(into stats: inout SystemStats) {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let gib = 1024.0 * 1024.0 * 1024.0
        let pageSize = Double(vm_kernel_page_size)
        // Activity Monitor: App Memory = anonymous ("internal") pages minus purgeable ones.
        let app = Double(vmStats.internal_page_count &- min(vmStats.internal_page_count, vmStats.purgeable_count)) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize
        let cached = Double(vmStats.external_page_count &+ vmStats.purgeable_count) * pageSize

        stats.ramApp = app / gib
        stats.ramWired = wired / gib
        stats.ramCompressed = compressed / gib
        stats.ramCached = cached / gib
        stats.ramUsed = min((app + wired + compressed) / gib, stats.ramTotal)
        stats.memoryPressure = MemoryPressure(sysctlLevel: getSysctlInt("kern.memorystatus_vm_pressure_level"))
    }

    // MARK: Storage

    private func updateStorage(into stats: inout SystemStats) {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            // Finder reports decimal GB and counts purgeable space as available; match it.
            let div = 1_000_000_000.0
            let total = Double(values.volumeTotalCapacity ?? 0)
            let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            stats.diskTotal = total / div
            stats.diskUsed = max(total - available, 0) / div
        }
    }

    // MARK: GPU

    private func updateGPU(into stats: inout SystemStats) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        var busiest: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let perf = property as? [String: Any],
               let utilization = (perf["Device Utilization %"] as? NSNumber)?.doubleValue {
                busiest = max(busiest ?? 0, utilization)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        if let busiest { stats.gpuUsage = min(max(busiest, 0), 100) }
    }

    // MARK: Network

    /// Sums 64-bit byte counters of the physical `en*` interfaces. The older `getifaddrs`
    /// counters are 32-bit and wrap every 4 GiB, which silently produced zero-speed samples.
    private func readNetworkCounters() -> (in: UInt64, out: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self)
                let messageLength = Int(header.pointee.ifm_msglen)
                guard messageLength > 0 else { break }

                if Int32(header.pointee.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.pointee.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        let flags = Int32(info.pointee.ifm_flags)
                        if name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 {
                            received &+= info.pointee.ifm_data.ifi_ibytes
                            sent &+= info.pointee.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += messageLength
            }
        }
        return (received, sent)
    }

    private func updateNetwork(into stats: inout SystemStats) {
        guard let counters = readNetworkCounters() else { return }
        let now = Date()
        if let last = lastNetData {
            let elapsed = now.timeIntervalSince(last.time)
            if elapsed > 0 {
                // A counter going backwards means an interface was reset; treat that sample as idle.
                stats.networkDownload = counters.in >= last.in ? Double(counters.in - last.in) / elapsed : 0
                stats.networkUpload = counters.out >= last.out ? Double(counters.out - last.out) / elapsed : 0
            }
        }
        lastNetData = (counters.in, counters.out, now)
    }

    // MARK: Temperature & fans

    private func updateTemperature(into stats: inout SystemStats) {
        if let reading = thermalSensors?.read() {
            stats.temperature = reading.dieAverage
            stats.temperatureMax = reading.dieMax
            stats.ssdTemperature = reading.ssd
            stats.batteryTemperature = reading.battery
        } else {
            stats.temperature = nil
            stats.temperatureMax = nil
            stats.ssdTemperature = nil
            stats.batteryTemperature = nil
        }
    }

    private func updateFans(into stats: inout SystemStats) {
        stats.fans = smc?.readFans() ?? []
    }

    // MARK: Processes

    private func updateProcesses(into stats: inout SystemStats) {
        let now = Date()
        let elapsed = now.timeIntervalSince(previousProcessSampleTime)
        previousProcessSampleTime = now

        var newCPUTimes: [pid_t: Double] = [:]
        var results: [ProcessStats] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }

            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { infoPtr -> Int32 in
                infoPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
                }
            }
            guard result == 0 else { continue }

            let totalCPUTimeNs = Double(info.ri_user_time + info.ri_system_time)
            newCPUTimes[pid] = totalCPUTimeNs

            var cpuPercent: Double = 0
            if elapsed > 0, let prevTime = previousProcessCPUTime[pid] {
                let deltaNs = totalCPUTimeNs - prevTime
                if deltaNs > 0 {
                    cpuPercent = (deltaNs / 1_000_000_000) / elapsed * 100
                }
            }

            let ramMB = Double(info.ri_phys_footprint) / (1024 * 1024)

            results.append(ProcessStats(id: pid, name: app.localizedName ?? "Unknown", icon: app.icon, cpuUsage: cpuPercent, ramUsageMB: ramMB))
        }

        previousProcessCPUTime = newCPUTimes
        stats.topProcesses = results.sorted { $0.cpuUsage > $1.cpuUsage }
    }

    // MARK: Static info

    func getMacCPUName() -> String { cpuName }

    private static func readCPUName() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var cpuString = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &cpuString, &size, nil, 0)
        return String(cString: cpuString)
    }
}
