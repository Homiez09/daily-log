import Foundation
import IOKit

public struct TemperatureReading: Equatable {
    /// Average across the SoC die sensors (what Activity-style monitors report as "CPU temperature").
    public var dieAverage: Double
    public var dieMax: Double
    public var ssd: Double?
    public var battery: Double?
}

/// Reads the Apple Silicon PMU/NAND/battery temperature sensors through the (private but
/// long-stable) IOHIDEventSystemClient API. No entitlements or root are needed. All symbols
/// are resolved with dlsym so a future removal degrades to "no reading" instead of a crash.
public final class ThermalSensors {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatFn = @convention(c) (CFTypeRef, Int32) -> Double

    // kIOHIDEventTypeTemperature = 15; field = type << 16.
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private let client: CFTypeRef
    private let copyServices: CopyServicesFn
    private let copyProperty: CopyPropertyFn
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn

    public init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let createPtr = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatchingPtr = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServicesPtr = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyPropertyPtr = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let copyEventPtr = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloatPtr = dlsym(handle, "IOHIDEventGetFloatValue")
        else { return nil }

        let create = unsafeBitCast(createPtr, to: CreateFn.self)
        let setMatching = unsafeBitCast(setMatchingPtr, to: SetMatchingFn.self)
        guard let created = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        // Usage page 0xff00 / usage 5 = Apple vendor temperature sensors.
        setMatching(created, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005] as CFDictionary)

        client = created
        copyServices = unsafeBitCast(copyServicesPtr, to: CopyServicesFn.self)
        copyProperty = unsafeBitCast(copyPropertyPtr, to: CopyPropertyFn.self)
        copyEvent = unsafeBitCast(copyEventPtr, to: CopyEventFn.self)
        getFloat = unsafeBitCast(getFloatPtr, to: GetFloatFn.self)
    }

    /// Every named sensor with its current value in °C.
    public func readAll() -> [(name: String, celsius: Double)] {
        guard let services = copyServices(client)?.takeRetainedValue() as [AnyObject]? else { return [] }
        var readings: [(String, Double)] = []
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue()
            else { continue }
            let value = getFloat(event, Self.temperatureField)
            // Sensors that are not populated report 0 or absurd values; drop them.
            if value > 5, value < 150 { readings.append((name, value)) }
        }
        return readings
    }

    public func read() -> TemperatureReading? {
        Self.summarize(readAll())
    }

    /// Pure aggregation, separated so it can be unit-tested with fixed inputs.
    public static func summarize(_ readings: [(name: String, celsius: Double)]) -> TemperatureReading? {
        let die = readings.filter { $0.name.lowercased().contains("tdie") }.map(\.celsius)
        guard !die.isEmpty else { return nil }
        let ssd = readings.filter { $0.name.uppercased().hasPrefix("NAND") }.map(\.celsius)
        let battery = readings.filter { $0.name.lowercased().contains("battery") }.map(\.celsius)
        return TemperatureReading(
            dieAverage: die.reduce(0, +) / Double(die.count),
            dieMax: die.max() ?? 0,
            ssd: ssd.max(),
            battery: battery.isEmpty ? nil : battery.reduce(0, +) / Double(battery.count)
        )
    }
}
