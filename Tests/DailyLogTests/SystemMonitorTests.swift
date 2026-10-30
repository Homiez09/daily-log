import XCTest
@testable import DailyLog

final class SystemMonitorTests: XCTestCase {
    var monitor: SystemMonitorManager!

    override func setUp() {
        super.setUp()
        monitor = SystemMonitorManager()
    }

    override func tearDown() {
        monitor = nil
        super.tearDown()
    }

    /// Runs `refreshStats()` and waits for its asynchronous main-queue publish.
    private func refreshAndWait(after delay: TimeInterval = 0.1) {
        monitor.refreshStats()
        let expectation = XCTestExpectation(description: "stats published")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { expectation.fulfill() }
        wait(for: [expectation], timeout: delay + 2.0)
    }

    func testRAMCalculations() {
        // Initial check for physical memory
        XCTAssertGreaterThan(monitor.stats.ramTotal, 0, "Physical memory should be detected")

        monitor.refreshStats()

        let expectation = XCTestExpectation(description: "Wait for main thread update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.monitor.stats.ramUsed >= 0)
            XCTAssertTrue(self.monitor.stats.ramUsed <= self.monitor.stats.ramTotal)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testMemoryBreakdownMatchesActivityMonitorDefinition() {
        refreshAndWait()
        let stats = monitor.stats
        XCTAssertGreaterThan(stats.ramApp, 0)
        XCTAssertGreaterThan(stats.ramWired, 0)
        // "Memory Used" = App + Wired + Compressed (cached files are deliberately excluded).
        XCTAssertEqual(stats.ramUsed, stats.ramApp + stats.ramWired + stats.ramCompressed, accuracy: 0.01)
        XCTAssertLessThan(stats.ramUsed, stats.ramTotal)
    }

    func testStorageCalculations() {
        monitor.refreshStats()

        let expectation = XCTestExpectation(description: "Wait for storage update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertGreaterThan(self.monitor.stats.diskTotal, 0)
            XCTAssertTrue(self.monitor.stats.diskUsed > 0)
            XCTAssertTrue(self.monitor.stats.diskUsed <= self.monitor.stats.diskTotal)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testCPUNeedsTwoSamplesAndKeepsCoresAlignedWithTheirTypes() {
        refreshAndWait(after: 1.0)
        refreshAndWait(after: 0.2)
        let stats = monitor.stats
        XCTAssertFalse(stats.perCoreUsage.isEmpty)
        XCTAssertEqual(stats.perCoreUsage.count, monitor.coreTypes.count, "one usage value per core, idle or not")
        XCTAssertTrue((0...100).contains(stats.cpuUsage), "cpu \(stats.cpuUsage)")
        for usage in stats.perCoreUsage { XCTAssertTrue((0...100).contains(usage)) }
    }

    func testNetworkRatesAreFiniteAndNeverNegative() {
        refreshAndWait(after: 1.0)
        refreshAndWait(after: 0.2)
        XCTAssertTrue(monitor.stats.networkDownload.isFinite && monitor.stats.networkDownload >= 0)
        XCTAssertTrue(monitor.stats.networkUpload.isFinite && monitor.stats.networkUpload >= 0)
    }

    func testTemperatureIsARealSensorReadingOrExplicitlyUnavailable() {
        refreshAndWait()
        if let temperature = monitor.stats.temperature {
            XCTAssertTrue((10...120).contains(temperature), "temperature \(temperature)")
            XCTAssertNotNil(monitor.stats.temperatureMax)
        } else {
            XCTAssertNil(monitor.stats.temperatureMax, "no fabricated fallback value")
        }
    }

    func testProgressValuesAreAlwaysClampedForTheMenuBar() {
        var stats = SystemStats()
        stats.cpuUsage = 250
        stats.gpuUsage = -5
        stats.ramTotal = 16
        stats.ramUsed = 40
        stats.temperature = 500
        stats.networkDownload = .infinity
        for metric in MenuBarMetric.allCases {
            let value = monitor.progressValue(for: metric, stats: stats)
            XCTAssertTrue((0...1).contains(value), "\(metric) -> \(value)")
        }
    }
}
