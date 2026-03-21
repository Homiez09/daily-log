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
}
