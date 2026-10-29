import Foundation

public struct MetricSnapshot: Codable, Sendable, Equatable {
    public static let protocolVersion = 1

    public let version: Int
    public let machineName: String
    public let timestamp: Date
    public let cpuFraction: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?
    public let diskFreeBytes: UInt64?
    public let diskTotalBytes: UInt64?
    public let networkReceivedBytesPerSecond: Double?
    public let networkSentBytesPerSecond: Double?
    public let batteryFraction: Double?
    public let isCharging: Bool?

    public init(
        machineName: String,
        timestamp: Date = .now,
        cpuFraction: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryTotalBytes: UInt64? = nil,
        diskFreeBytes: UInt64? = nil,
        diskTotalBytes: UInt64? = nil,
        networkReceivedBytesPerSecond: Double? = nil,
        networkSentBytesPerSecond: Double? = nil,
        batteryFraction: Double? = nil,
        isCharging: Bool? = nil
    ) {
        self.version = Self.protocolVersion
        self.machineName = machineName
        self.timestamp = timestamp
        self.cpuFraction = cpuFraction
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.networkReceivedBytesPerSecond = networkReceivedBytesPerSecond
        self.networkSentBytesPerSecond = networkSentBytesPerSecond
        self.batteryFraction = batteryFraction
        self.isCharging = isCharging
    }
}

public enum MetricFormat {
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return (fraction * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    public static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .file) + "/s"
    }
}
