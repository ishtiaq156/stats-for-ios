import ActivityCore
import Darwin
import Foundation
import IOKit.ps

final class SystemSampler {
    private var previousCPU: (used: UInt64, total: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?

    func sample() -> MetricSnapshot {
        let date = Date()
        let cpu = cpuUsage()
        let memory = memoryUsage()
        let disk = diskUsage()
        let network = networkRates(at: date)
        let battery = batteryStatus()

        return MetricSnapshot(
            machineName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            timestamp: date,
            cpuFraction: cpu,
            memoryUsedBytes: memory?.used,
            memoryTotalBytes: memory?.total,
            diskFreeBytes: disk?.free,
            diskTotalBytes: disk?.total,
            networkReceivedBytesPerSecond: network?.received,
            networkSentBytesPerSecond: network?.sent,
            batteryFraction: battery?.fraction,
            isCharging: battery?.charging
        )
    }

    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let used = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) + UInt64(info.cpu_ticks.2)
        let total = used + UInt64(info.cpu_ticks.3)
        defer { previousCPU = (used, total) }
        guard let previousCPU, total > previousCPU.total, used >= previousCPU.used else { return nil }
        return min(1, Double(used - previousCPU.used) / Double(total - previousCPU.total))
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64)? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * page
        return (min(used, ProcessInfo.processInfo.physicalMemory), ProcessInfo.processInfo.physicalMemory)
    }

    private func diskUsage() -> (free: UInt64, total: UInt64)? {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return (UInt64(max(0, free)), UInt64(max(0, total)))
    }

    private func networkRates(at date: Date) -> (received: Double, sent: Double)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor = head
        while let item = cursor {
            let address = item.pointee.ifa_addr
            if address?.pointee.sa_family == UInt8(AF_LINK),
               item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let data = item.pointee.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(counters.ifi_ibytes)
                sent += UInt64(counters.ifi_obytes)
            }
            cursor = item.pointee.ifa_next
        }
        defer { previousNetwork = (received, sent, date) }
        guard let previousNetwork, received >= previousNetwork.received,
              sent >= previousNetwork.sent else { return nil }
        let elapsed = date.timeIntervalSince(previousNetwork.date)
        guard elapsed > 0 else { return nil }
        return (Double(received - previousNetwork.received) / elapsed,
                Double(sent - previousNetwork.sent) / elapsed)
    }

    private func batteryStatus() -> (fraction: Double, charging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return (min(1, Double(current) / Double(maximum)), charging)
        }
        return nil
    }
}
