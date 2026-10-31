import Foundation
import XCTest
@testable import ActivityCore

final class SecurePacketTests: XCTestCase {
    func testAuthenticatedPacketRoundTripAndTamperRejection() throws {
        let key = Data(repeating: 0x42, count: 32)
        let otherKey = Data(repeating: 0x43, count: 32)
        let message = Data("snapshot.v1".utf8)
        let sealed = try SecurePacket.seal(message, using: key)

        XCTAssertEqual(try SecurePacket.open(sealed, using: key), message)
        XCTAssertThrowsError(try SecurePacket.open(sealed, using: otherKey))

        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertThrowsError(try SecurePacket.open(tampered, using: key))
    }

    func testFrameRejectsOversizedOrEmptyPackets() {
        let framed = SecurePacket.frame(Data(repeating: 7, count: 128))
        XCTAssertEqual(SecurePacket.length(framed.prefix(4)), 128)
        XCTAssertNil(SecurePacket.length(Data([0, 0, 0, 0])))
        XCTAssertNil(SecurePacket.length(Data([0, 16, 0, 1])))
    }

    func testFrameHandlesLargeHistoryResponse() {
        let payload = Data(repeating: 7, count: 66_242)
        let framed = SecurePacket.frame(payload)
        XCTAssertEqual(SecurePacket.length(framed.prefix(4)), payload.count)
        XCTAssertEqual(framed.dropFirst(4), payload)
    }
}
