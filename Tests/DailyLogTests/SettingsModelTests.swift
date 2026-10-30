import XCTest
@testable import DailyLog

final class SettingsModelTests: XCTestCase {
    func testSettingsSavedBeforeFanSupportStillDecode() throws {
        // Exactly what v1.0.0 wrote: none of the fan / second-metric / colour keys exist.
        let legacy = """
        {"showHeader":true,"showSystemMonitor":true,"showProductiveApps":false,"showHistoryButton":true,
         "showProcessMonitor":true,"menuBarLeading":"GPU","menuBarTrailing":"RAM","menuBarStyle":"Wave",
         "cpuAlertThreshold":70,"ramAlertThreshold":900}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(UISettings.self, from: legacy)
        XCTAssertEqual(settings.menuBarLeading, .gpu)
        XCTAssertEqual(settings.menuBarStyle, .wave)
        XCTAssertFalse(settings.showProductiveApps)
        XCTAssertEqual(settings.fanControlMode, .auto)
        XCTAssertEqual(settings.fanManualFraction, 0.5)
        XCTAssertFalse(settings.showTrailingMetric)
        XCTAssertFalse(settings.menuBarColored)
        XCTAssertFalse(settings.liquidGlassCards, "real glass cards must stay opt-in: they cost GPU")
    }

    func testLiquidGlassCardsIsOffByDefaultAndPersists() throws {
        XCTAssertFalse(UISettings().liquidGlassCards)
        var settings = UISettings()
        settings.liquidGlassCards = true
        let decoded = try JSONDecoder().decode(UISettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.liquidGlassCards)
    }

    func testWholeGameStateFromV1StillLoads() throws {
        let v1 = #"{"totalLifetimeExp":1234,"productiveApps":[],"allTimeStats":{}}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(GameState.self, from: v1)
        XCTAssertEqual(state.totalLifetimeExp, 1234)
        XCTAssertEqual(state.uiSettings.fanControlMode, .auto)
    }

    func testCorruptFanFractionIsClamped() throws {
        for (stored, expected) in [("9.5", 1.0), ("-2", 0.0), ("0.25", 0.25)] {
            let json = "{\"fanManualFraction\":\(stored)}".data(using: .utf8)!
            XCTAssertEqual(try JSONDecoder().decode(UISettings.self, from: json).fanManualFraction, expected)
        }
    }

    func testSettingsRoundTrip() throws {
        var settings = UISettings()
        settings.fanControlMode = .manual
        settings.fanManualFraction = 0.8
        settings.menuBarLeading = .fan
        settings.showTrailingMetric = true
        settings.menuBarColored = true
        let decoded = try JSONDecoder().decode(UISettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.fanControlMode, .manual)
        XCTAssertEqual(decoded.fanManualFraction, 0.8)
        XCTAssertEqual(decoded.menuBarLeading, .fan)
        XCTAssertTrue(decoded.showTrailingMetric)
        XCTAssertTrue(decoded.menuBarColored)
    }
}

final class FormatTests: XCTestCase {
    func testNetworkRateFormatting() {
        XCTAssertEqual(Format.rate(0), "0 KB/s")
        XCTAssertEqual(Format.rate(100), "<1 KB/s")
        XCTAssertEqual(Format.rate(154 * 1024), "154 KB/s")
        XCTAssertEqual(Format.rate(1.5 * 1024 * 1024), "1.5 MB/s")
        XCTAssertEqual(Format.rate(.nan), "0 KB/s")
        XCTAssertEqual(Format.compactRate(154 * 1024), "154K")
        XCTAssertEqual(Format.compactRate(2.5 * 1024 * 1024), "2.5M")
    }

    func testTemperatureAndRPMFormatting() {
        XCTAssertEqual(Format.celsius(nil), "—")
        XCTAssertEqual(Format.celsius(48.6), "49°")
        XCTAssertEqual(Format.percent(24.4), "24%")
        XCTAssertEqual(Format.percent(.nan), "0%")
        XCTAssertEqual(Format.rpm(1518.57).replacingOccurrences(of: ",", with: ""), "1519")
    }
}
