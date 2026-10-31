import CryptoKit
import Foundation

public enum SecurePacket {
    public static let serviceType = "_macactivity._tcp"

    public static func seal(_ data: Data, using keyData: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: keyData))
        guard let combined = box.combined else { throw PacketError.invalidCiphertext }
        return combined
    }

    public static func open(_ data: Data, using keyData: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: keyData))
    }

    public static func frame(_ data: Data) -> Data {
        let count = UInt32(data.count)
        return Data([
            UInt8(truncatingIfNeeded: count >> 24),
            UInt8(truncatingIfNeeded: count >> 16),
            UInt8(truncatingIfNeeded: count >> 8),
            UInt8(truncatingIfNeeded: count)
        ]) + data
    }

    public static func length(_ header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let bytes = Array(header)
        let count = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        guard count > 0, count <= 1_000_000 else { return nil }
        return Int(count)
    }

    public enum PacketError: Error {
        case invalidCiphertext
    }
}
