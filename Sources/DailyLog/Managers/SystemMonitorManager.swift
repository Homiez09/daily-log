import Foundation
import IOKit
import AppKit

enum CPUCoreType {
    case efficiency
    case performance
    case unknown
}

class SystemMonitorManager: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var perCoreUsage: [Double] = []
    @Published var coreTypes: [CPUCoreType] = [] // NEW: Type of each core
    
    @Published var ramUsed: Double = 0
    @Published var ramTotal: Double = 0
    @Published var gpuUsage: Double = 0
    @Published var diskUsed: Double = 0
    @Published var diskTotal: Double = 0
    @Published var networkDownload: Double = 0
    @Published var networkUpload: Double = 0
    @Published var temperature: Double = 0
    
    private var timer: Timer?
    private var previousProcessorInfo: processor_info_array_t?
    private var previousProcessorInfoCount: mach_msg_type_number_t = 0
    private var lastNetData: (in: UInt64, out: UInt64, time: Date)?
    
    init() {
        self.ramTotal = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        detectCoreTypes()
        updateStorage()
        startMonitoring()
    }
    
    // MARK: - Core Detection (Apple Silicon)
    private func detectCoreTypes() {
        // In Apple Silicon, cores are usually grouped: E-cores first, then P-cores.
        // We use sysctl to get the counts for perflevel0 (P) and perflevel1 (E).
        let eCoreCount = getSysctlInt("hw.perflevel1.logicalcpu") // Efficiency
        let pCoreCount = getSysctlInt("hw.perflevel0.logicalcpu") // Performance
        let totalCores = ProcessInfo.processInfo.activeProcessorCount
        
        var types: [CPUCoreType] = []
        
        // Strategy: fill E-cores first, then P-cores (standard macOS order)
        for _ in 0..<eCoreCount { types.append(.efficiency) }
        for _ in 0..<pCoreCount { types.append(.performance) }
        
        // Fallback if sysctl fails or returns 0
        if types.isEmpty {
            for _ in 0..<totalCores { types.append(.unknown) }
        }
        
        self.coreTypes = types
    }
    
    private func getSysctlInt(_ name: String) -> Int {
        var size = MemoryLayout<Int>.size
        var value = Int()
        if sysctlbyname(name, &value, &size, nil, 0) == 0 {
            return value
        }
        return 0
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStats()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func refreshStats() {
        updateCPU()
        updateRAM()
        updateGPU()
        updateNetwork()
        updateTemperature()
        updateStorage()
    }
    
    private func updateCPU() {
        var processorCount: mach_msg_type_number_t = 0
        var processorInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &infoCount)
        
        if result == KERN_SUCCESS, let info = processorInfo {
            var coreUsages: [Double] = []
            var totalCombinedUsage: Double = 0
            
            for i in 0..<Int(processorCount) {
                let index = i * Int(CPU_STATE_MAX)
                let user = info[index + Int(CPU_STATE_USER)]
                let system = info[index + Int(CPU_STATE_SYSTEM)]
                let idle = info[index + Int(CPU_STATE_IDLE)]
                let nice = info[index + Int(CPU_STATE_NICE)]
                
                if let prevInfo = previousProcessorInfo {
                    let prevUser = prevInfo[index + Int(CPU_STATE_USER)]
                    let prevSystem = prevInfo[index + Int(CPU_STATE_SYSTEM)]
                    let prevIdle = prevInfo[index + Int(CPU_STATE_IDLE)]
                    let prevNice = prevInfo[index + Int(CPU_STATE_NICE)]
                    
                    let diffUser = user - prevUser
                    let diffSystem = system - prevSystem
                    let diffIdle = idle - prevIdle
                    let diffNice = nice - prevNice
                    let total = diffUser + diffSystem + diffIdle + diffNice
                    
                    if total > 0 {
                        let usage = Double(diffUser + diffSystem + diffNice) / Double(total) * 100.0
                        coreUsages.append(usage)
                        totalCombinedUsage += usage
                    }
                }
            }
            
            if let prev = previousProcessorInfo {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(previousProcessorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
            }
            
            previousProcessorInfo = info
            previousProcessorInfoCount = infoCount
            
            DispatchQueue.main.async {
                self.perCoreUsage = coreUsages
                if !coreUsages.isEmpty {
                    self.cpuUsage = totalCombinedUsage / Double(coreUsages.count)
                }
            }
        }
    }
    
    private func updateRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
            DispatchQueue.main.async { self.ramUsed = Double(usedPages * pageSize) / (1024 * 1024 * 1024) }
        }
    }
    
    private func updateStorage() {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let divider = 1_000_000_000.0
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            if let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacityForImportantUsage {
                let t = Double(total)
                let a = Double(available)
                DispatchQueue.main.async {
                    self.diskTotal = t / divider
                    self.diskUsed = (t - a) / divider
                }
            }
        } catch { print(error) }
    }
    
    private func updateGPU() {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = properties?.takeRetainedValue() as? [String: Any],
                   let stats = dict["PerformanceStatistics"] as? [String: Any] {
                    let utilization = stats["Device Utilization %"] as? Int ?? 0
                    DispatchQueue.main.async { self.gpuUsage = Double(utilization) }
                    IOObjectRelease(service)
                    break 
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
    }
    
    private func updateTemperature() {
        let state = ProcessInfo.processInfo.thermalState
        var base: Double = 38.0
        switch state {
        case .nominal: base = 38.0; case .fair: base = 48.0; case .serious: base = 65.0; case .critical: base = 82.0; @unknown default: base = 35.0
        }
        DispatchQueue.main.async { self.temperature = base + (self.cpuUsage / 10.0) }
    }
    
    private func updateNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }
        var currentIn: UInt64 = 0; var currentOut: UInt64 = 0
        var ptr = ifaddr
        while ptr != nil {
            let flags = Int32(ptr!.pointee.ifa_flags)
            let name = String(cString: ptr!.pointee.ifa_name)
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if name.hasPrefix("en") || name.hasPrefix("ap") {
                    if let data = ptr!.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self)
                        currentIn += UInt64(networkData.pointee.ifi_ibytes)
                        currentOut += UInt64(networkData.pointee.ifi_obytes)
                    }
                }
            }
            ptr = ptr!.pointee.ifa_next
        }
        let now = Date()
        if let last = lastNetData {
            let diff = now.timeIntervalSince(last.time)
            if diff > 0 {
                DispatchQueue.main.async {
                    self.networkDownload = Double(currentIn - last.in) / (1024 * 1024) / diff
                    self.networkUpload = Double(currentOut - last.out) / (1024 * 1024) / diff
                }
            }
        }
        lastNetData = (currentIn, currentOut, now)
    }
}
