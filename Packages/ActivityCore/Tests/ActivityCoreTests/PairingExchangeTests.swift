import Foundation
import XCTest
@testable import ActivityCore

final class PairingExchangeTests: XCTestCase {
    func testMatchingCodesDeriveTheSameSessionKey() throws {
        let phone = try PairingExchange(role: .phone, code: "47877")
        let mac = try PairingExchange(role: .mac, code: "47877")
        let phoneKey = try phone.finish(peerMessage: mac.message)
        let macKey = try mac.finish(peerMessage: phone.message)
        XCTAssertEqual(phoneKey, macKey)
        XCTAssertEqual(phoneKey.count, 32)
    }

    func testWrongCodeCannotOpenConfirmation() throws {
        let phone = try PairingExchange(role: .phone, code: "00000")
        let mac = try PairingExchange(role: .mac, code: "47877")
        let phoneKey = try phone.finish(peerMessage: mac.message)
        let macKey = try mac.finish(peerMessage: phone.message)
        let confirmation = try SecurePacket.seal(PairingWire.confirmation, using: phoneKey)
        XCTAssertThrowsError(try SecurePacket.open(confirmation, using: macKey))
    }

    func testExchangeIsSingleUse() throws {
        let phone = try PairingExchange(role: .phone, code: "47877")
        let mac = try PairingExchange(role: .mac, code: "47877")
        _ = try phone.finish(peerMessage: mac.message)
        XCTAssertThrowsError(try phone.finish(peerMessage: mac.message))
    }
}
