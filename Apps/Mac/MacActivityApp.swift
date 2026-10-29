import ActivityCore
import CoreImage.CIFilterBuiltins
import SwiftUI

@MainActor
final class MacActivityModel: ObservableObject {
    @Published private(set) var snapshot: MetricSnapshot
    private let sampler = SystemSampler()
    private var timer: Timer?
    private var server: MetricServer?

    var setupKey: String { server?.setupKey.base64EncodedString() ?? "" }

    init() {
        snapshot = sampler.sample()
        server = MetricServer(snapshot: { [weak self] in
            self?.snapshot ?? MetricSnapshot(machineName: "Mac")
        })
        server?.start()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() { snapshot = sampler.sample() }

    func revokeAllPhones() {
        server?.stop()
        MetricServer.revokeAllPhones()
        server = MetricServer(snapshot: { [weak self] in
            self?.snapshot ?? MetricSnapshot(machineName: "Mac")
        })
        server?.start()
        objectWillChange.send()
    }
}

@main
struct MacActivityApp: App {
    @StateObject private var model = MacActivityModel()

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
                Button("Quit Mac Activity") { NSApplication.shared.terminate(nil) }
            }
            .padding(14)
            .frame(width: 300)
        } label: {
            Label("Mac Activity", systemImage: "chart.xyaxis.line")
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
