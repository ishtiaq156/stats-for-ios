import Foundation
import Spake2FFI

public final class PairingExchange {
    public enum Role { case phone, mac }
    public enum ExchangeError: Error { case invalidCode, invalidPeerMessage, alreadyFinished }

    private var state: UnsafeMutableRawPointer?
    public let message: Data

    public init(role: Role, code: String) throws {
        let bytes = Array(code.utf8)
        guard bytes.count == 5, bytes.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw ExchangeError.invalidCode
        }
        var output = [UInt8](repeating: 0, count: 33)
        let pointer = bytes.withUnsafeBufferPointer { codeBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                stats_spake2_start(role == .phone ? 0 : 1, codeBuffer.baseAddress,
                                   codeBuffer.count, outputBuffer.baseAddress, outputBuffer.count)
            }
        }
        guard let pointer else { throw ExchangeError.invalidCode }
        state = pointer
        message = Data(output)
    }

    deinit {
        if let state { stats_spake2_free(state) }
    }

    public func finish(peerMessage: Data) throws -> Data {
        guard let pointer = state else { throw ExchangeError.alreadyFinished }
        state = nil
        var key = [UInt8](repeating: 0, count: 32)
        let result = peerMessage.withUnsafeBytes { peerBuffer in
            key.withUnsafeMutableBufferPointer { keyBuffer in
                stats_spake2_finish(pointer, peerBuffer.bindMemory(to: UInt8.self).baseAddress,
                                    peerMessage.count, keyBuffer.baseAddress, keyBuffer.count)
            }
        }
        guard result == 0 else { throw ExchangeError.invalidPeerMessage }
        return Data(key)
    }
}
