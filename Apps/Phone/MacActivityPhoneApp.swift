import ActivityCore
import SwiftUI

@main
struct MacActivityPhoneApp: App {
    var body: some Scene {
        WindowGroup { OverviewView() }
    }
}

private struct OverviewView: View {
    @StateObject private var nearby = NearbyMacStore()
    @State private var preview = PreviewSnapshot()
    @State private var showPairing = false

    private var displayed: MetricSnapshot {
        nearby.snapshot ?? (nearby.selectedName == nil
            ? preview.snapshot : MetricSnapshot(machineName: nearby.selectedName ?? "Mac"))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    deviceHeader
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                        Text(nearby.selectedName == nil
                             ? "Preview values · add your Mac to see live activity"
                             : nearby.status)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        MetricCard(title: "CPU", icon: "cpu", tint: .orange,
                                   value: MetricFormat.percent(displayed.cpuFraction),
                                   detail: "Processor load", fraction: displayed.cpuFraction)
                        MetricCard(title: "Memory", icon: "memorychip", tint: .purple,
                                   value: MetricFormat.bytes(displayed.memoryUsedBytes),
                                   detail: "of \(MetricFormat.bytes(displayed.memoryTotalBytes)) used",
                                   fraction: fraction(displayed.memoryUsedBytes, displayed.memoryTotalBytes))
                        MetricCard(title: "Storage", icon: "internaldrive", tint: .blue,
                                   value: MetricFormat.bytes(displayed.diskFreeBytes),
                                   detail: "free of \(MetricFormat.bytes(displayed.diskTotalBytes))",
                                   fraction: diskUsedFraction(displayed))
                        NetworkCard(snapshot: displayed)
                    }
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Mac Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPairing = true } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Add Mac")
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if nearby.selectedName == nil { preview.advance() }
            }
        }
        .sheet(isPresented: $showPairing) { PairingView(store: nearby) }
    }

    private func fraction(_ used: UInt64?, _ total: UInt64?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    private func diskUsedFraction(_ snapshot: MetricSnapshot) -> Double? {
        guard let free = snapshot.diskFreeBytes, let total = snapshot.diskTotalBytes, total > 0 else { return nil }
        return 1 - Double(free) / Double(total)
    }

    private var deviceHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayed.machineName).font(.headline)
                Text(nearby.selectedName == nil ? "Demo Mac · sample data" : nearby.status)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

private struct PairingView: View {
    @ObservedObject var store: NearbyMacStore
    @Environment(\.dismiss) private var dismiss
    @State private var pairingDevice: NearbyMacStore.Device?
    @State private var key = ""
    @State private var invalidKey = false
    @State private var showPairingChoices = false
    @State private var showKeyPrompt = false
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.devices.isEmpty {
                        ContentUnavailableView("Looking for Macs", systemImage: "desktopcomputer.and.arrow.down",
                                               description: Text("Open Mac Activity on your Mac and keep both devices on the same network."))
                    } else {
                        ForEach(store.devices) { device in
                            Button {
                                if store.select(device) { dismiss() }
                                else {
                                    pairingDevice = device
                                    key = ""
                                    showPairingChoices = true
                                }
                            } label: {
                                HStack {
                                    Label(device.name, systemImage: "desktopcomputer")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                } header: { Text("Nearby Macs") }
                footer: { Text("The Mac menu shows a setup key. Pair once, then the key is saved securely on this iPhone.") }

                if store.selectedName != nil {
                    Section {
                        Button("Forget current Mac", role: .destructive) { store.forget() }
                    }
                }
            }
            .navigationTitle("Add Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Pair with \(pairingDevice?.name ?? "Mac")", isPresented: $showPairingChoices) {
                Button("Scan QR code") { showScanner = true }
                Button("Paste setup key") { showKeyPrompt = true }
            } message: { Text("Open Mac Activity in your Mac menu bar.") }
            .alert("Enter setup key", isPresented: $showKeyPrompt) {
                TextField("Paste the key from your Mac", text: $key)
                Button("Pair") {
                    if let pairingDevice, store.pair(pairingDevice, keyString: key) { dismiss() }
                    else { invalidKey = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Copy the setup key from the Mac Activity menu bar app.") }
            .alert("Invalid setup key", isPresented: $invalidKey) {
                Button("OK") {}
            } message: { Text("Copy the full key shown on your Mac and try again.") }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRCodeScanner { code in
                        showScanner = false
                        if let pairingDevice, store.pair(pairingDevice, keyString: code) { dismiss() }
                        else { invalidKey = true }
                    } onUnavailable: {
                        showScanner = false
                        showKeyPrompt = true
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan Mac code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { showScanner = false } } }
                }
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let icon: String
    let tint: Color
    let value: String
    let detail: String
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 32, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            if let fraction {
                GeometryReader { proxy in
                    Capsule().fill(tint.opacity(0.13))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint)
                                .frame(width: proxy.size.width * min(1, max(0, fraction)))
                        }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

private struct NetworkCard: View {
    let snapshot: MetricSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Network", systemImage: "network")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            HStack(spacing: 20) {
                rate("Down", icon: "arrow.down", value: snapshot.networkReceivedBytesPerSecond)
                rate("Up", icon: "arrow.up", value: snapshot.networkSentBytesPerSecond)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func rate(_ name: String, icon: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(name, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(MetricFormat.rate(value))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PreviewSnapshot {
    private var tick = 0
    private(set) var snapshot = MetricSnapshot(
        machineName: "Your Mac",
        cpuFraction: 0.27,
        memoryUsedBytes: 8_400_000_000,
        memoryTotalBytes: 16_000_000_000,
        diskFreeBytes: 241_000_000_000,
        diskTotalBytes: 500_000_000_000,
        networkReceivedBytesPerSecond: 1_400_000,
        networkSentBytesPerSecond: 230_000
    )

    var memoryFraction: Double? {
        guard let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    var diskUsedFraction: Double? {
        guard let free = snapshot.diskFreeBytes, let total = snapshot.diskTotalBytes, total > 0 else { return nil }
        return 1 - Double(free) / Double(total)
    }

    mutating func advance() {
        tick += 1
        let wave = sin(Double(tick) * 0.65)
        snapshot = MetricSnapshot(
            machineName: "Your Mac",
            cpuFraction: 0.28 + wave * 0.12,
            memoryUsedBytes: UInt64(8_400_000_000 + wave * 300_000_000),
            memoryTotalBytes: 16_000_000_000,
            diskFreeBytes: 241_000_000_000,
            diskTotalBytes: 500_000_000_000,
            networkReceivedBytesPerSecond: 1_400_000 + wave * 600_000,
            networkSentBytesPerSecond: 230_000 + wave * 100_000
        )
    }
}
