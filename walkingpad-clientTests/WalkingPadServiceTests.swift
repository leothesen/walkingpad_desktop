import XCTest
@testable import walkingpad_client

final class WalkingPadServiceTests: XCTestCase {
    
    func testSumFrom() {
        XCTAssertEqual(WalkingPadService.sumFrom([0x01, 0x02]), 258)
        XCTAssertEqual(WalkingPadService.sumFrom([0x01, 0x02, 0x03]), 66051)
        XCTAssertEqual(WalkingPadService.sumFrom([0x00, 0x00, 0x01]), 1)
        XCTAssertEqual(WalkingPadService.sumFrom([0xFF]), 255)
    }
    
    func testStatusTypeFrom() {
        XCTAssertEqual(WalkingPadService.statusTypeFrom([248, 162, 0]), .currentStatus)
        XCTAssertEqual(WalkingPadService.statusTypeFrom([248, 167, 0]), .lastStatus)
        XCTAssertNil(WalkingPadService.statusTypeFrom([247, 162, 0]))
        XCTAssertNil(WalkingPadService.statusTypeFrom([0, 0, 0]))
    }
}
