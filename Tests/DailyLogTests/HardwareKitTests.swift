import XCTest
@testable import HardwareKit

final class FanCurveTests: XCTestCase {
    func testEndpointsMapToHardwareLimits() {
        XCTAssertEqual(FanCurve.rpm(forFraction: 0, min: 1499, max: 4296), 1499)
        XCTAssertEqual(FanCurve.rpm(forFraction: 1, min: 1499, max: 4296), 4296)
    }

    func testMidpointIsRoundedToWholeRPM() {
        // 1499 + 0.5 * 2797 = 2897.5 -> 2898
        XCTAssertEqual(FanCurve.rpm(forFraction: 0.5, min: 1499, max: 4296), 2898)
    }

    func testOutOfRangeAndInvalidInputsNeverLeaveTheSafeRange() {
        XCTAssertEqual(FanCurve.rpm(forFraction: -3, min: 1499, max: 4296), 1499)
        XCTAssertEqual(FanCurve.rpm(forFraction: 9, min: 1499, max: 4296), 4296)
        XCTAssertEqual(FanCurve.rpm(forFraction: .nan, min: 1499, max: 4296), 1499)
        XCTAssertEqual(FanCurve.rpm(forFraction: .infinity, min: 1499, max: 4296), 4296)
        // Corrupt hardware limits fall back to the minimum instead of producing garbage.
        XCTAssertEqual(FanCurve.rpm(forFraction: 0.5, min: 3000, max: 1000), 3000)
    }

    func testEachFanUsesItsOwnRange() {
        XCTAssertEqual(FanCurve.rpm(forFraction: 1, min: 1499, max: 4296), 4296)
        XCTAssertEqual(FanCurve.rpm(forFraction: 1, min: 1499, max: 4744), 4744)
    }

    func testInverseMapping() {
        XCTAssertEqual(FanCurve.fraction(forRPM: 2898, min: 1499, max: 4296), 0.5, accuracy: 0.001)
        XCTAssertEqual(FanCurve.fraction(forRPM: 100, min: 1499, max: 4296), 0)
        XCTAssertEqual(FanCurve.fraction(forRPM: 9999, min: 1499, max: 4296), 1)
    }
}

final class SMCValueTests: XCTestCase {
    func testFloatRoundTrip() throws {
        let bytes = try XCTUnwrap(SMCValue.encode(1522, type: "flt ", size: 4))
        XCTAssertEqual(bytes.count, 4)
        XCTAssertEqual(SMCValue(key: "F0Tg", type: "flt ", bytes: bytes).doubleValue, 1522)
    }

    func testFloatDecodesRealHardwareBytes() {
        // Bytes read from F0Mx on an M1 Pro: 4296 RPM.
        XCTAssertEqual(SMCValue(key: "F0Mx", type: "flt ", bytes: [0, 64, 134, 69]).doubleValue, 4296)
    }

    func testFixedPointTypes() throws {
        XCTAssertEqual(SMCValue(key: "x", type: "fpe2", bytes: [0x1F, 0x40]).doubleValue, 2000)
        XCTAssertEqual(SMCValue(key: "x", type: "sp78", bytes: [0x32, 0x80]).doubleValue, 50.5)
        // ioft: 48.16 fixed point, little-endian (TG0B on real hardware -> 37.4 °C)
        let ioft = SMCValue(key: "TG0B", type: "ioft", bytes: [102, 102, 37, 0, 0, 0, 0, 0]).doubleValue
        XCTAssertEqual(try XCTUnwrap(ioft), 37.4, accuracy: 0.01)

        let encoded = try XCTUnwrap(SMCValue.encode(2000, type: "fpe2", size: 2))
        XCTAssertEqual(encoded, [0x1F, 0x40])
    }

    func testIntegerTypesAndMismatchedSizes() {
        XCTAssertEqual(SMCValue(key: "FNum", type: "ui8 ", bytes: [2]).doubleValue, 2)
        XCTAssertEqual(SMCValue(key: "x", type: "ui32", bytes: [0, 0, 8, 131]).doubleValue, 2179)
        XCTAssertNil(SMCValue(key: "x", type: "flt ", bytes: [1, 2]).doubleValue, "wrong size must not be decoded")
        XCTAssertNil(SMCValue(key: "x", type: "hex_", bytes: [1]).doubleValue)
        XCTAssertNil(SMCValue.encode(1, type: "hex_", size: 1))
        XCTAssertNil(SMCValue.encode(1, type: "flt ", size: 2), "size must match the key's declared size")
    }

    func testEncodeClampsInsteadOfOverflowing() {
        XCTAssertEqual(SMCValue.encode(1000, type: "ui8 ", size: 1), [255])
        XCTAssertEqual(SMCValue.encode(-5, type: "ui8 ", size: 1), [0])
    }
}

final class FanProtocolTests: XCTestCase {
    func testParsesValidCommands() {
        XCTAssertEqual(FanCommand(line: "AUTO"), .auto)
        XCTAssertEqual(FanCommand(line: "auto\n"), .auto)
        XCTAssertEqual(FanCommand(line: "PING"), .ping)
        XCTAssertEqual(FanCommand(line: "MANUAL 0.5"), .manual(fraction: 0.5))
        XCTAssertEqual(FanCommand(line: "MANUAL 0"), .manual(fraction: 0))
        XCTAssertEqual(FanCommand(line: "MANUAL 1"), .manual(fraction: 1))
    }

    func testRejectsMalformedOrOutOfRangeCommands() {
        for line in ["", "MANUAL", "MANUAL 1.5", "MANUAL -0.1", "MANUAL abc", "MANUAL nan", "MANUAL inf",
                     "AUTO now", "PING extra", "REBOOT", "MANUAL 0.5 0.5", "rm -rf /"] {
            XCTAssertNil(FanCommand(line: line), "'\(line)' must be rejected")
        }
    }

    func testCommandsSurviveASerializationRoundTrip() {
        for command in [FanCommand.auto, .ping, .manual(fraction: 0.4375)] {
            XCTAssertEqual(FanCommand(line: command.line), command)
        }
    }

    func testSocketPathIsPerUserAndInRootOwnedDirectory() {
        XCTAssertEqual(FanControlPaths.socketPath(uid: 501), "/var/run/com.user.DailyLog.fan.501.sock")
        XCTAssertNotEqual(FanControlPaths.socketPath(uid: 501), FanControlPaths.socketPath(uid: 502))
    }

    func testLineBufferHandlesPartialAndMultipleLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Array("MAN".utf8)), [])
        XCTAssertEqual(buffer.append(Array("UAL 0.5\nAUTO\nPI".utf8)), ["MANUAL 0.5", "AUTO"])
        XCTAssertEqual(buffer.append(Array("NG\n".utf8)), ["PING"])
    }

    func testLineBufferDropsUnboundedGarbage() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append([UInt8](repeating: 0x41, count: 5000)), [])
        XCTAssertEqual(buffer.append(Array("AUTO\n".utf8)), ["AUTO"], "buffer must recover after an oversized line")
    }
}

final class FanSafetyTests: XCTestCase {
    func testEmergencyThresholdForcesAutomaticMode() {
        XCTAssertFalse(FanSafety.shouldForceAuto(dieMax: 80))
        XCTAssertFalse(FanSafety.shouldForceAuto(dieMax: 94.9))
        XCTAssertTrue(FanSafety.shouldForceAuto(dieMax: 95))
        XCTAssertTrue(FanSafety.shouldForceAuto(dieMax: 110))
    }

    func testMissingSensorNeverTriggersAnEmergencyButRaisesTheFloor() {
        XCTAssertFalse(FanSafety.shouldForceAuto(dieMax: nil))
        XCTAssertEqual(FanSafety.allowedFraction(requested: 0, dieMax: nil), FanSafety.minimumFractionWithoutSensor)
        XCTAssertEqual(FanSafety.allowedFraction(requested: 0.8, dieMax: nil), 0.8)
        XCTAssertEqual(FanSafety.allowedFraction(requested: 0, dieMax: 50), 0)
    }
}

final class ThermalSummaryTests: XCTestCase {
    func testAveragesOnlyDieSensors() throws {
        let readings: [(name: String, celsius: Double)] = [
            ("PMU tdie1", 50), ("PMU tdie2", 60), ("PMU tdie3", 70),
            ("PMU tdev1", 99), ("gas gauge battery", 35), ("NAND CH0 temp", 40)
        ]
        let summary = try XCTUnwrap(ThermalSensors.summarize(readings))
        XCTAssertEqual(summary.dieAverage, 60, accuracy: 0.001)
        XCTAssertEqual(summary.dieMax, 70)
        XCTAssertEqual(summary.ssd, 40)
        XCTAssertEqual(summary.battery, 35)
    }

    func testNoDieSensorsMeansNoReadingRatherThanAFakeOne() {
        XCTAssertNil(ThermalSensors.summarize([]))
        XCTAssertNil(ThermalSensors.summarize([("gas gauge battery", 35)]))
    }
}

/// Reads the real SMC of the machine running the tests (read-only; nothing is ever written).
final class SMCHardwareReadTests: XCTestCase {
    func testFanReadingsAreInternallyConsistent() throws {
        let smc: SMCConnection
        do { smc = try SMCConnection() } catch { throw XCTSkip("AppleSMC not available: \(error)") }
        let fans = smc.readFans()
        if fans.isEmpty { throw XCTSkip("This Mac has no fans (e.g. MacBook Air)") }
        XCTAssertEqual(fans.count, smc.fanCount)
        for fan in fans {
            XCTAssertGreaterThan(fan.maxRPM, fan.minRPM, "fan \(fan.index) range")
            XCTAssertGreaterThanOrEqual(fan.currentRPM, 0)
            XCTAssertLessThanOrEqual(fan.currentRPM, fan.maxRPM * 1.25, "fan \(fan.index) reading is implausible")
            XCTAssertTrue((0...1).contains(fan.fraction))
        }
    }

    func testTemperatureSensorsReturnPhysicallyPlausibleValues() throws {
        guard let sensors = ThermalSensors() else { throw XCTSkip("IOHID temperature API unavailable") }
        guard let reading = sensors.read() else { throw XCTSkip("No die sensors on this Mac") }
        XCTAssertTrue((10...120).contains(reading.dieAverage), "die average \(reading.dieAverage)")
        XCTAssertGreaterThanOrEqual(reading.dieMax, reading.dieAverage)
    }
}
