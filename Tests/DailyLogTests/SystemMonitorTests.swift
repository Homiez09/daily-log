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
        XCTAssertGreaterThan(monitor.ramTotal, 0, "Physical memory should be detected")
        monitor.refreshStats()
        
        let expectation = XCTestExpectation(description: "Wait for main thread update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.monitor.ramUsed >= 0)
            XCTAssertTrue(self.monitor.ramUsed <= self.monitor.ramTotal)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testStorageCalculations() {
        monitor.refreshStats()
        
        let expectation = XCTestExpectation(description: "Wait for storage update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertGreaterThan(self.monitor.diskTotal, 0)
            XCTAssertTrue(self.monitor.diskUsed > 0)
            XCTAssertTrue(self.monitor.diskUsed <= self.monitor.diskTotal)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
