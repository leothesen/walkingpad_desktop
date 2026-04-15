import XCTest
@testable import walkingpad_client

final class WalkingPadCommandTests: XCTestCase {
    
    func testChecksumCalculation() {
        // [0xF7, 0xA2, 1, 25, 0xff, 0xFD] -> checksum for [0xA2, 1, 25] should be 162 + 1 + 25 = 188 (0xBC)
        let input: [UInt8] = [247, 162, 1, 25, 0xff, 253]
        let expected: [UInt8] = [247, 162, 1, 25, 188, 253]
        
        let result = WalkingPadCommand.fixChecksum(values: input)
        XCTAssertEqual(result, expected, "Checksum should be the sum of bytes between start and end markers")
    }
    
    func testChecksumOverflow() {
        // [0xF7, 0xA2, 1, 255, 0xff, 0xFD] -> checksum for [0xA2, 1, 255] should be (162 + 1 + 255) % 256 = 162
        let input: [UInt8] = [247, 162, 1, 255, 0xff, 253]
        let expected: [UInt8] = [247, 162, 1, 255, 162, 253]
        
        let result = WalkingPadCommand.fixChecksum(values: input)
        XCTAssertEqual(result, expected, "Checksum should handle UInt8 wrapping overflow correctly")
    }

    func testBypassNoviceGuideCommand() {
        // [0xF7, 0xA2, 10, 1, 173, 0xFD] -> checksum: 162 + 10 + 1 = 173
        let input: [UInt8] = [247, 162, 10, 1, 0xff, 253]
        let expected: [UInt8] = [247, 162, 10, 1, 173, 253]
        
        let result = WalkingPadCommand.fixChecksum(values: input)
        XCTAssertEqual(result, expected, "Bypass Novice Guide command sequence should match with correct checksum")
    }

    func testStartCommand() {
        // [0xF7, 0xA2, 4, 1, 167, 0xFD] -> checksum: 162 + 4 + 1 = 167
        let input: [UInt8] = [247, 162, 4, 1, 0xff, 253]
        let expected: [UInt8] = [247, 162, 4, 1, 167, 253]
        
        let result = WalkingPadCommand.fixChecksum(values: input)
        XCTAssertEqual(result, expected, "Start command sequence should match with correct checksum")
    }

    func testStopCommand() {
        // [0xF7, 0xA2, 4, 2, 168, 0xFD] -> checksum: 162 + 4 + 2 = 168
        // Note: the original test used 0 for stop, but WalkingPadCommand.stop() uses 2.
        let input: [UInt8] = [247, 162, 4, 2, 0xff, 253]
        let expected: [UInt8] = [247, 162, 4, 2, 168, 253]
        
        let result = WalkingPadCommand.fixChecksum(values: input)
        XCTAssertEqual(result, expected, "Stop command sequence should match with correct checksum")
    }

    func testSetManualModeCommand() {
        // [0xF7, 0xA2, 2, 1, 165, 0xFD] -> checksum: 162 + 2 + 1 = 165
        let input: [UInt8] = [247, 162, 2, 1, 0xff, 253]
        let expected: [UInt8] = [247, 162, 2, 1, 165, 253]
        
        let result = WalkingPadCommand.fixChecksum(values: input)
        XCTAssertEqual(result, expected, "Set Manual Mode command sequence should match with correct checksum")
    }

    func testStandbyCommand() {
        // [0xF7, 0xA2, 2, 2, 166, 0xFD] -> checksum: 162 + 2 + 2 = 166
        let input: [UInt8] = [247, 162, 2, 2, 0xff, 253]
        let expected: [UInt8] = [247, 162, 2, 2, 166, 253]
        
        let result = WalkingPadCommand.fixChecksum(values: input)
        XCTAssertEqual(result, expected, "Standby command sequence should match with correct checksum")
    }
}
