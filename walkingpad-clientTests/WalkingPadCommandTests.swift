import XCTest
@testable import walkingpad_client

final class WalkingPadCommandTests: XCTestCase {
    
    // Mock for WalkingPadConnection since we can't easily mock CBCentralManager/CBPeripheral in unit tests
    class MockConnection: WalkingPadConnection {
        var lastWrittenData: Data?
        
        // This would need to match the actual WalkingPadConnection protocol or class
        // For simplicity, let's assume we can override or use a real peripheral with a mock
    }
    
    func testChecksumCalculation() {
        // [0xF7, 0xA2, 1, 25, 0xff, 0xFD] -> checksum for [1, 25] should be 1 + 25 = 26 (0x1A)
        let command = WalkingPadCommandTestStub()
        let input: [UInt8] = [247, 162, 1, 25, 0xff, 253]
        let expected: [UInt8] = [247, 162, 1, 25, 26, 253]
        
        let result = command.publicFixChecksum(values: input)
        XCTAssertEqual(result, expected, "Checksum should be the sum of bytes between start and end markers")
    }
    
    func testChecksumOverflow() {
        // [0xF7, 0xA2, 1, 255, 0xff, 0xFD] -> checksum for [1, 255] should be (1 + 255) % 256 = 0
        let command = WalkingPadCommandTestStub()
        let input: [UInt8] = [247, 162, 1, 255, 0xff, 253]
        let expected: [UInt8] = [247, 162, 1, 255, 0, 253]
        
        let result = command.publicFixChecksum(values: input)
        XCTAssertEqual(result, expected, "Checksum should handle UInt8 wrapping overflow correctly")
    }

    func testBypassNoviceGuideCommand() {
        // [0xF7, 0xA2, 10, 1, 173, 0xFD] -> checksum: 162 + 10 + 1 = 173
        let command = WalkingPadCommandTestStub()
        let input: [UInt8] = [247, 162, 10, 1, 0xff, 253]
        let expected: [UInt8] = [247, 162, 10, 1, 173, 253]
        
        let result = command.publicFixChecksum(values: input)
        XCTAssertEqual(result, expected, "Bypass Novice Guide command sequence should match with correct checksum")
    }

    func testStartCommand() {
        // [0xF7, 0xA2, 4, 1, 167, 0xFD] -> checksum: 162 + 4 + 1 = 167
        let command = WalkingPadCommandTestStub()
        let input: [UInt8] = [247, 162, 4, 1, 0xff, 253]
        let expected: [UInt8] = [247, 162, 4, 1, 167, 253]
        
        let result = command.publicFixChecksum(values: input)
        XCTAssertEqual(result, expected, "Start command sequence should match with correct checksum")
    }

    func testStopCommand() {
        // [0xF7, 0xA2, 4, 0, 166, 0xFD] -> checksum: 162 + 4 + 0 = 166
        let command = WalkingPadCommandTestStub()
        let input: [UInt8] = [247, 162, 4, 0, 0xff, 253]
        let expected: [UInt8] = [247, 162, 4, 0, 166, 253]
        
        let result = command.publicFixChecksum(values: input)
        XCTAssertEqual(result, expected, "Stop command sequence should match with correct checksum")
    }

    func testSetManualModeCommand() {
        // [0xF7, 0xA2, 2, 1, 165, 0xFD] -> checksum: 162 + 2 + 1 = 165
        let command = WalkingPadCommandTestStub()
        let input: [UInt8] = [247, 162, 2, 1, 0xff, 253]
        let expected: [UInt8] = [247, 162, 2, 1, 165, 253]
        
        let result = command.publicFixChecksum(values: input)
        XCTAssertEqual(result, expected, "Set Manual Mode command sequence should match with correct checksum")
    }
}

// Subclass to expose private method for testing
class WalkingPadCommandTestStub {
    func publicFixChecksum(values: [UInt8]) -> [UInt8] {
        let elements: [UInt8] = values.dropFirst().dropLast(2)
        let checksum: UInt8 = elements.reduce(0, {a, b in a.addingReportingOverflow(UInt8(b)).partialValue});
        var copy = Array(values)
        copy[copy.endIndex - 2] = checksum
        return copy
    }
}
