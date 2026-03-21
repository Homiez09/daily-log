import Foundation
import IOKit
import AppKit

enum CPUCoreType {
    case efficiency
    case performance
    case unknown
}

struct SystemStats {
    var cpuUsage: Double = 0
    var perCoreUsage: [Double] = []
    var gpuUsage: Double = 0
    var ramUsed: Double = 0
    var ramTotal: Double = 0
    var diskUsed: Double = 0
    var diskTotal: Double = 0
    var networkDownload: Double = 0
    var networkUpload: Double = 0
    var temperature: Double = 0
}

class SystemMonitorManager: ObservableObject {
    @Published var stats = SystemStats()
    @Published var coreTypes: [CPUCoreType] = []
    
    private var timer: Timer?
    private var previousProcessorInfo: processor_info_array_t?
    private var previousProcessorInfoCount: mach_msg_type_number_t = 0
    private var lastNetData: (in: UInt64, out: UInt64, time: Date)?
    
    init() {
        self.stats.ramTotal = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        detectCoreTypes()
        refreshStats()
        startMonitoring()
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
    
    private func detectCoreTypes() {
        let eCoreCount = getSysctlInt("hw.perflevel1.logicalcpu")
        let pCoreCount = getSysctlInt("hw.perflevel0.logicalcpu")
        let totalCores = ProcessInfo.processInfo.activeProcessorCount
        var types: [CPUCoreType] = []
        for _ in 0..<eCoreCount { types.append(.efficiency) }
        for _ in 0..<pCoreCount { types.append(.performance) }
        if types.isEmpty {
            for _ in 0..<totalCores { types.append(.unknown) }
        }
        self.coreTypes = types
    }
    
    private func getSysctlInt(_ name: String) -> Int {
        var size = MemoryLayout<Int>.size
        var value = Int()
        if sysctlbyname(name, &value, &size, nil, 0) == 0 { return value }
        return 0
    }
    
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
        
        // 1. CPU
        updateCPU(into: &newStats)
        // 2. RAM
        updateRAM(into: &newStats)
        // 3. GPU
        updateGPU(into: &newStats)
        // 4. Storage
        updateStorage(into: &newStats)
        // 5. Network
        updateNetwork(into: &newStats)
        // 6. Temp
        updateTemperature(into: &newStats)
        
        DispatchQueue.main.async {
            self.stats = newStats
        }
    }
    
    private func updateCPU(into stats: inout SystemStats) {
        var processorCount: mach_msg_type_number_t = 0
        var processorInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &infoCount)
        
        if result == KERN_SUCCESS, let info = processorInfo {
            var coreUsages: [Double] = []
            var totalCombined: Double = 0
            
            for i in 0..<Int(processorCount) {
                let index = i * Int(CPU_STATE_MAX)
                
                let user = UInt32(bitPattern: info[index + Int(CPU_STATE_USER)])
                let system = UInt32(bitPattern: info[index + Int(CPU_STATE_SYSTEM)])
                let idle = UInt32(bitPattern: info[index + Int(CPU_STATE_IDLE)])
                let nice = UInt32(bitPattern: info[index + Int(CPU_STATE_NICE)])
                
                if let prev = previousProcessorInfo {
                    let pUser = UInt32(bitPattern: prev[index + Int(CPU_STATE_USER)])
                    let pSystem = UInt32(bitPattern: prev[index + Int(CPU_STATE_SYSTEM)])
                    let pIdle = UInt32(bitPattern: prev[index + Int(CPU_STATE_IDLE)])
                    let pNice = UInt32(bitPattern: prev[index + Int(CPU_STATE_NICE)])
                    
                    let diffUser = user &- pUser
                    let diffSystem = system &- pSystem
                    let diffIdle = idle &- pIdle
                    let diffNice = nice &- pNice
                    
                    let diffTotal = UInt64(diffUser) + UInt64(diffSystem) + UInt64(diffIdle) + UInt64(diffNice)
                    if diffTotal > 0 {
                        let active = UInt64(diffUser) + UInt64(diffSystem) + UInt64(diffNice)
                        let usage = Double(active) / Double(diffTotal) * 100.0
                        coreUsages.append(usage)
                        totalCombined += usage
                    }
                }
            }
            
            if let prev = previousProcessorInfo {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: Int(bitPattern: prev)), vm_size_t(previousProcessorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
            }
            
            previousProcessorInfo = info
            previousProcessorInfoCount = infoCount
            
            stats.perCoreUsage = coreUsages
            if !coreUsages.isEmpty {
                stats.cpuUsage = totalCombined / Double(coreUsages.count)
            }
        }
    }
    
    private func updateRAM(into stats: inout SystemStats) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        if host_statistics64(mach_host_self(), HOST_VM_INFO64, withUnsafeMutablePointer(to: &vmStats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { $0 } }, &count) == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let used = UInt64(vmStats.active_count + vmStats.wire_count + vmStats.compressor_page_count) * pageSize
            stats.ramUsed = Double(used) / (1024 * 1024 * 1024)
        }
    }
    
    private func updateStorage(into stats: inout SystemStats) {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            let div = 1_000_000_000.0
            stats.diskTotal = Double(values.volumeTotalCapacity ?? 0) / div
            stats.diskUsed = (Double(values.volumeTotalCapacity ?? 0) - Double(values.volumeAvailableCapacityForImportantUsage ?? 0)) / div
        }
    }
    
    private func updateGPU(into stats: inout SystemStats) {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any],
                   let perf = dict["PerformanceStatistics"] as? [String: Any] {
                    stats.gpuUsage = Double(perf["Device Utilization %"] as? Int ?? 0)
                    IOObjectRelease(service)
                    break
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
    }
    
    private func updateNetwork(into stats: inout SystemStats) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }
        var cin: UInt64 = 0; var cout: UInt64 = 0
        var ptr = ifaddr
        while ptr != nil {
            let name = String(cString: ptr!.pointee.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("ap") {
                if let data = ptr!.pointee.ifa_data {
                    let nd = data.assumingMemoryBound(to: if_data.self)
                    cin += UInt64(nd.pointee.ifi_ibytes); cout += UInt64(nd.pointee.ifi_obytes)
                }
            }
            ptr = ptr!.pointee.ifa_next
        }
        let now = Date()
        if let last = lastNetData {
            let diff = now.timeIntervalSince(last.time)
            if diff > 0 {
                let downloadDiff = cin >= last.in ? cin - last.in : 0
                let uploadDiff = cout >= last.out ? cout - last.out : 0
                
                stats.networkDownload = Double(downloadDiff) / (1024*1024) / diff
                stats.networkUpload = Double(uploadDiff) / (1024*1024) / diff
            }
        }
        lastNetData = (cin, cout, now)
    }
    
    private func updateTemperature(into stats: inout SystemStats) {
        let state = ProcessInfo.processInfo.thermalState
        var base = 38.0
        switch state {
        case .nominal: base = 38.0; case .fair: base = 48.0; case .serious: base = 65.0; case .critical: base = 82.0; @unknown default: base = 35.0
        }
        stats.temperature = base + (stats.cpuUsage / 10.0)
    }
}
