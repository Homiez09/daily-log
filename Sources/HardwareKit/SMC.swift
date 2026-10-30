import Foundation
import IOKit
import CSMC

public enum SMCError: Error, CustomStringConvertible, Equatable {
    case serviceNotFound
    case openFailed(Int32)
    case keyNotFound(String)
    case callFailed(kernelResult: Int32, smcResult: UInt8)
    case sizeMismatch(key: String, expected: Int, got: Int)
    case unsupportedType(key: String, type: String)
    case verificationFailed(String)

    public var description: String {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found"
        case .openFailed(let kr): return "Could not open AppleSMC (kern_return \(kr))"
        case .keyNotFound(let key): return "SMC key \(key) does not exist on this Mac"
        case .callFailed(let kr, let smc): return "SMC call failed (kern_return \(kr), result \(smc))"
        case .sizeMismatch(let key, let expected, let got): return "SMC key \(key) expects \(expected) bytes, got \(got)"
        case .unsupportedType(let key, let type): return "SMC key \(key) has unsupported type '\(type)'"
        case .verificationFailed(let what): return "SMC did not accept the change: \(what)"
        }
    }
}

public struct SMCValue: Equatable {
    public let key: String
    public let type: String
    public let bytes: [UInt8]

    /// Decodes the numeric SMC types used for fans and temperatures.
    public var doubleValue: Double? {
        switch type {
        case "flt " where bytes.count == 4:
            // Apple Silicon stores floats in native (little-endian) byte order.
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "fpe2" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case "ioft" where bytes.count == 8:
            // 48.16 fixed point, little-endian.
            var raw: UInt64 = 0
            for (i, b) in bytes.enumerated() { raw |= UInt64(b) << (8 * UInt64(i)) }
            return Double(raw) / 65536.0
        default:
            return nil
        }
    }

    /// Encodes a number for writing back to a key of the given type.
    public static func encode(_ value: Double, type: String, size: Int) -> [UInt8]? {
        switch type {
        case "flt " where size == 4:
            let bits = Float(value).bitPattern
            return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF)]
        case "fpe2" where size == 2:
            let raw = UInt16(max(0, min(value * 4.0, Double(UInt16.max))))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "ui8 " where size == 1:
            return [UInt8(max(0, min(value, 255)))]
        case "ui16" where size == 2:
            let raw = UInt16(max(0, min(value, Double(UInt16.max))))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        default:
            return nil
        }
    }
}

/// Thin wrapper around the AppleSMC IOKit user client. Reads work for any user;
/// writes are only accepted by the SMC when the calling process is root.
public final class SMCConnection {
    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: SMCKeyInfoData] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { throw SMCError.openFailed(result) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public static func fourCC(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    public static func string(fromFourCC code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private func call(_ input: SMCKeyData) throws -> SMCKeyData {
        var input = input
        var output = SMCKeyData()
        var outputSize = Int(smc_struct_size())
        let kr = IOConnectCallStructMethod(connection, UInt32(kSMCHandleYPCEvent), &input, Int(smc_struct_size()), &output, &outputSize)
        guard kr == KERN_SUCCESS, output.result == 0 else {
            throw SMCError.callFailed(kernelResult: kr, smcResult: output.result)
        }
        return output
    }

    private func keyInfo(_ key: String) throws -> SMCKeyInfoData {
        let code = Self.fourCC(key)
        if let cached = infoCache[code] { return cached }
        var input = SMCKeyData()
        input.key = code
        input.data8 = UInt8(kSMCCommandGetKeyInfo)
        do {
            let output = try call(input)
            infoCache[code] = output.keyInfo
            return output.keyInfo
        } catch {
            throw SMCError.keyNotFound(key)
        }
    }

    public func keyExists(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    public func read(_ key: String) throws -> SMCValue {
        let info = try keyInfo(key)
        var input = SMCKeyData()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = UInt8(kSMCCommandReadKey)
        let output = try call(input)
        var bytes = [UInt8](repeating: 0, count: Int(info.dataSize))
        var out = output
        smc_get_bytes(&out, &bytes, info.dataSize)
        return SMCValue(key: key, type: Self.string(fromFourCC: info.dataType), bytes: bytes)
    }

    public func readDouble(_ key: String) -> Double? {
        try? read(key).doubleValue
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        guard bytes.count == Int(info.dataSize) else {
            throw SMCError.sizeMismatch(key: key, expected: Int(info.dataSize), got: bytes.count)
        }
        var input = SMCKeyData()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = UInt8(kSMCCommandWriteKey)
        smc_set_bytes(&input, bytes, info.dataSize)
        _ = try call(input)
    }

    public func write(_ key: String, number: Double) throws {
        let info = try keyInfo(key)
        let type = Self.string(fromFourCC: info.dataType)
        guard let bytes = SMCValue.encode(number, type: type, size: Int(info.dataSize)) else {
            throw SMCError.unsupportedType(key: key, type: type)
        }
        try write(key, bytes: bytes)
    }

    /// Names of every key the SMC exposes (used for diagnostics and sensor discovery).
    public func allKeys() -> [String] {
        guard let count = readDouble("#KEY") else { return [] }
        var names: [String] = []
        for index in 0..<Int(count) {
            var input = SMCKeyData()
            input.data8 = UInt8(kSMCCommandGetKeyFromIndex)
            input.data32 = UInt32(index)
            if let output = try? call(input) {
                names.append(Self.string(fromFourCC: output.key))
            }
        }
        return names
    }
}
