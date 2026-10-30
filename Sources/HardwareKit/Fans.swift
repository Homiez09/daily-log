import Foundation

public struct FanReading: Equatable, Identifiable {
    public let index: Int
    public var currentRPM: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var targetRPM: Double
    /// True when the SMC reports the fan is under manual (forced) control.
    public var isManual: Bool

    public var id: Int { index }

    /// Current speed as a 0...1 position inside this fan's own min...max range.
    public var fraction: Double {
        guard maxRPM > 0 else { return 0 }
        return min(max(currentRPM / maxRPM, 0), 1)
    }

    public init(index: Int, currentRPM: Double, minRPM: Double, maxRPM: Double, targetRPM: Double, isManual: Bool) {
        self.index = index
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
        self.isManual = isManual
    }
}

/// Maps the user-facing 0...1 slider onto each fan's own hardware range. Fans on one Mac
/// commonly have different maximums (e.g. 4296 / 4744 RPM), so the setting is a fraction, not an RPM.
public enum FanCurve {
    public static func rpm(forFraction fraction: Double, min minRPM: Double, max maxRPM: Double) -> Double {
        // NaN or corrupt hardware limits fall back to the minimum; ±infinity is just an out-of-range request.
        guard !fraction.isNaN, minRPM.isFinite, maxRPM.isFinite, maxRPM >= minRPM else { return minRPM }
        let clamped = Swift.min(Swift.max(fraction, 0), 1)
        return (minRPM + clamped * (maxRPM - minRPM)).rounded()
    }

    /// Inverse mapping, used to show the RPM a slider position will produce.
    public static func fraction(forRPM rpm: Double, min minRPM: Double, max maxRPM: Double) -> Double {
        guard maxRPM > minRPM else { return 0 }
        return Swift.min(Swift.max((rpm - minRPM) / (maxRPM - minRPM), 0), 1)
    }
}

public extension SMCConnection {
    var fanCount: Int {
        Int(readDouble("FNum") ?? 0)
    }

    /// Mode key is `F<n>Md` on current Macs; some firmware exposes it in lowercase.
    private func modeKey(forFan index: Int) -> String? {
        for candidate in ["F\(index)Md", "F\(index)md"] where keyExists(candidate) { return candidate }
        return nil
    }

    func readFans() -> [FanReading] {
        let count = fanCount
        guard count > 0, count < 8 else { return [] }
        var fans: [FanReading] = []
        for index in 0..<count {
            guard let actual = readDouble("F\(index)Ac"),
                  let minRPM = readDouble("F\(index)Mn"),
                  let maxRPM = readDouble("F\(index)Mx")
            else { continue }
            let target = readDouble("F\(index)Tg") ?? 0
            let mode = modeKey(forFan: index).flatMap { readDouble($0) } ?? 0
            fans.append(FanReading(index: index, currentRPM: actual, minRPM: minRPM, maxRPM: maxRPM, targetRPM: target, isManual: mode != 0))
        }
        return fans
    }

    // MARK: Writing (root only; the SMC rejects these calls from unprivileged processes)

    /// Forces every fan to `fraction` of its own range. Returns the fans as read back from the SMC.
    /// Throws if the SMC did not actually enter manual mode, so callers never claim success falsely.
    @discardableResult
    func setFansManual(fraction: Double, retryDelay: TimeInterval = 0.3, maxAttempts: Int = 12) throws -> [FanReading] {
        let fans = readFans()
        guard !fans.isEmpty else { throw SMCError.keyNotFound("F0Ac") }

        // Newer Apple Silicon firmware only lets thermalmonitord hand over control once the
        // diagnostic-unlock key is set. It does not exist on every Mac, so it is optional.
        if keyExists("Ftst") { try write("Ftst", number: 1) }

        for fan in fans {
            guard let modeKey = modeKey(forFan: fan.index) else { throw SMCError.keyNotFound("F\(fan.index)Md") }
            try writeVerified(modeKey, value: 1, retryDelay: retryDelay, maxAttempts: maxAttempts)
            let rpm = FanCurve.rpm(forFraction: fraction, min: fan.minRPM, max: fan.maxRPM)
            try write("F\(fan.index)Tg", number: rpm)
        }

        let readBack = readFans()
        for fan in readBack where !fan.isManual {
            throw SMCError.verificationFailed("fan \(fan.index) stayed in automatic mode")
        }
        return readBack
    }

    /// Hands control back to the system. Safe to call repeatedly.
    func setFansAuto(retryDelay: TimeInterval = 0.3, maxAttempts: Int = 12) throws {
        var firstError: Error?
        for fan in readFans() {
            guard let modeKey = modeKey(forFan: fan.index) else { continue }
            do { try writeVerified(modeKey, value: 0, retryDelay: retryDelay, maxAttempts: maxAttempts) }
            catch { firstError = firstError ?? error }
        }
        if keyExists("Ftst") { try? write("Ftst", number: 0) }
        if let firstError { throw firstError }
    }

    private func writeVerified(_ key: String, value: Double, retryDelay: TimeInterval, maxAttempts: Int) throws {
        var lastError: Error = SMCError.verificationFailed(key)
        for attempt in 0..<maxAttempts {
            do {
                try write(key, number: value)
                if readDouble(key) == value { return }
                lastError = SMCError.verificationFailed("\(key) did not read back as \(Int(value))")
            } catch {
                lastError = error
            }
            if attempt < maxAttempts - 1 { Thread.sleep(forTimeInterval: retryDelay) }
        }
        throw lastError
    }
}
