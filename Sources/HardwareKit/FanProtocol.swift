import Foundation

/// Line-based protocol between the app and the root fan helper, spoken over a Unix socket.
public enum FanCommand: Equatable {
    case auto
    case manual(fraction: Double)
    case ping

    public init?(line: String) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard let verb = parts.first?.uppercased() else { return nil }
        switch verb {
        case "AUTO" where parts.count == 1:
            self = .auto
        case "PING" where parts.count == 1:
            self = .ping
        case "MANUAL" where parts.count == 2:
            guard let value = Double(parts[1]), value.isFinite, (0...1).contains(value) else { return nil }
            self = .manual(fraction: value)
        default:
            return nil
        }
    }

    public var line: String {
        switch self {
        case .auto: return "AUTO"
        case .ping: return "PING"
        case .manual(let fraction): return String(format: "MANUAL %.4f", fraction)
        }
    }
}

public enum FanControlPaths {
    /// Lives in /var/run (root-owned directory) so an unprivileged process cannot pre-create or swap it.
    public static func socketPath(uid: uid_t) -> String {
        "/var/run/com.user.DailyLog.fan.\(uid).sock"
    }
}

public enum FanSafety {
    /// Die temperature (°C) at which the helper abandons manual mode and returns control to macOS.
    public static let emergencyDieTemperature: Double = 95
    /// Without a working temperature sensor the helper refuses to run fans below this fraction.
    public static let minimumFractionWithoutSensor: Double = 0.25
    /// The helper restores automatic control if it hears nothing from the app for this long.
    public static let watchdogSeconds: TimeInterval = 10

    /// Decides the fraction the helper may actually apply for a request.
    public static func allowedFraction(requested: Double, dieMax: Double?) -> Double {
        guard dieMax != nil else { return max(requested, minimumFractionWithoutSensor) }
        return requested
    }

    public static func shouldForceAuto(dieMax: Double?) -> Bool {
        guard let dieMax else { return false }
        return dieMax >= emergencyDieTemperature
    }
}
