import ActivityCore
import CoreImage.CIFilterBuiltins
import Darwin
import SwiftUI

@MainActor
final class StatsCompanionModel: ObservableObject {
    @Published private(set) var snapshot: MetricSnapshot
    private var recentSnapshots: [MetricSnapshot]
    @Published private(set) var localAddress: String?
    private let sampler = SystemSampler()
    private var timer: Timer?
    private var server: MetricServer?

    var setupKey: String { server?.setupKey.base64EncodedString() ?? "" }

    init() {
        let first = sampler.sample()
        snapshot = first
        recentSnapshots = [first]
        server = makeServer()
        server?.start()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        snapshot = sampler.sample()
        recentSnapshots.append(snapshot)
        if recentSnapshots.count > 900 {
            recentSnapshots.removeFirst(recentSnapshots.count - 900)
        }
    }

    func revokeAllPhones() {
        server?.stop()
        MetricServer.revokeAllPhones()
        server = makeServer()
        server?.start()
        objectWillChange.send()
    }

    private func makeServer() -> MetricServer {
        MetricServer(snapshot: { [weak self] in
            self?.snapshot ?? MetricSnapshot(machineName: "Mac")
        }, history: { [weak self] in
            self?.recentSnapshots ?? []
        }, onPort: { [weak self] port in
            self?.localAddress = Self.ipv4Address().map { "\($0):\(port)" }
        })
    }

    private static func ipv4Address() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var fallback: String?
        var cursor = head
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var bytes = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            guard inet_ntop(AF_INET, &ipv4, &bytes, socklen_t(bytes.count)) != nil else { continue }
            let value = String(cString: bytes)
            if String(cString: item.pointee.ifa_name) == "en0" { return value }
            if fallback == nil { fallback = value }
        }
        return fallback
    }
}

@main
struct StatsCompanionApp: App {
    @StateObject private var model = StatsCompanionModel()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.snapshot.machineName).font(.headline)
                LabeledContent("CPU", value: MetricFormat.percent(model.snapshot.cpuFraction))
                LabeledContent("Memory", value: "\(MetricFormat.bytes(model.snapshot.memoryUsedBytes)) / \(MetricFormat.bytes(model.snapshot.memoryTotalBytes))")
                LabeledContent("Disk free", value: MetricFormat.bytes(model.snapshot.diskFreeBytes))
                LabeledContent("Download", value: MetricFormat.rate(model.snapshot.networkReceivedBytesPerSecond))
                LabeledContent("Upload", value: MetricFormat.rate(model.snapshot.networkSentBytesPerSecond))
                if model.snapshot.batteryFraction != nil {
                    LabeledContent("Battery", value: MetricFormat.percent(model.snapshot.batteryFraction))
                }
                Divider()
                Text("Pair this Mac")
                    .font(.headline)
                if let address = model.localAddress {
                    LabeledContent("Local address", value: address)
                }
                Text("Copy this setup key into the iPhone app. Keep it private: it grants access to these metrics.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.setupKey)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                if let qr = qrImage(for: model.setupKey) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 170, height: 170)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Setup key QR code")
                }
                Button("Copy setup key") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.setupKey, forType: .string)
                }
                Button("Revoke all paired phones") { model.revokeAllPhones() }
                Button("Quit Stats Companion") { NSApplication.shared.terminate(nil) }
            }
            .padding(14)
            .frame(width: 300)
        } label: {
            Label("Stats Companion", systemImage: "chart.xyaxis.line")
        }
        .menuBarExtraStyle(.window)
    }

    private func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 170, height: 170))
    }
}
