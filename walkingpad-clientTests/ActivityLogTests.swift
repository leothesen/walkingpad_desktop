import XCTest
@testable import walkingpad_client

final class ActivityLogTests: XCTestCase {
    
    func testLogEntryCreation() {
        let log = ActivityLog()
        log.info("Test message")
        
        // Note: entries are updated on main queue async, 
        // so we need to wait a bit if we want to check the count.
        let expectation = self.expectation(description: "Log entry added")
        DispatchQueue.main.async {
            XCTAssertEqual(log.entries.count, 1)
            XCTAssertEqual(log.entries.first?.message, "Test message")
            XCTAssertEqual(log.entries.first?.type, .info)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMaxEntries() {
        let log = ActivityLog()
        let max = 100
        
        for i in 0..<(max + 10) {
            log.info("Message \(i)")
        }
        
        let expectation = self.expectation(description: "Log entries truncated")
        DispatchQueue.main.async {
            XCTAssertEqual(log.entries.count, max)
            XCTAssertEqual(log.entries.last?.message, "Message 109")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}
