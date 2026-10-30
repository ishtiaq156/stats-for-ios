import ActivityCore
import SwiftUI

@main
struct StatsApp: App {
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
                        NavigationLink {
                            MetricDetailView(kind: .cpu, store: nearby, preview: displayed)
                        } label: {
                            MetricCard(title: "CPU", icon: "cpu", tint: .orange,
                                       value: MetricFormat.percent(displayed.cpuFraction),
                                       detail: "Processor load", fraction: displayed.cpuFraction)
                        }
                        NavigationLink {
                            MetricDetailView(kind: .memory, store: nearby, preview: displayed)
                        } label: {
                            MetricCard(title: "Memory", icon: "memorychip", tint: .purple,
                                       value: MetricFormat.bytes(displayed.memoryUsedBytes),
                                       detail: "of \(MetricFormat.bytes(displayed.memoryTotalBytes)) used",
                                       fraction: fraction(displayed.memoryUsedBytes, displayed.memoryTotalBytes))
                        }
                        NavigationLink {
                            MetricDetailView(kind: .storage, store: nearby, preview: displayed)
                        } label: {
                            MetricCard(title: "Storage", icon: "internaldrive", tint: .blue,
                                       value: MetricFormat.bytes(displayed.diskFreeBytes),
                                       detail: "free of \(MetricFormat.bytes(displayed.diskTotalBytes))",
                                       fraction: diskUsedFraction(displayed))
                        }
                        NavigationLink {
                            MetricDetailView(kind: .network, store: nearby, preview: displayed)
                        } label: {
                            NetworkCard(snapshot: displayed)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Stats")
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
    @State private var showPasscodePrompt = false
    @State private var passcode = ""
    @State private var phoneName = "iPhone"
    @State private var manualPasscode = ""
    @State private var pairingError: String?
    @State private var isPairing = false
    @State private var manualHost = ""
    @State private var manualPort = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.devices.isEmpty {
                        ContentUnavailableView("Looking for Macs", systemImage: "desktopcomputer.and.arrow.down",
                                               description: Text("Open Stats Companion on your Mac and keep both devices on the same network."))
                    } else {
                        ForEach(store.devices) { device in
                            HStack {
                                Button {
                                    if store.select(device) { dismiss() }
                                    else {
                                        pairingDevice = device
                                        passcode = ""
                                        showPasscodePrompt = true
                                    }
                                } label: {
                                    Label(device.name, systemImage: "desktopcomputer")
                                }
                                Spacer()
                                if store.hasSavedPairing(device) {
                                    Button("Pair again") {
                                        pairingDevice = device
                                        passcode = ""
                                        showPasscodePrompt = true
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                } header: { Text("Nearby Macs") }
                footer: { Text("Open Pair new phone in the Mac menu and enter its five-digit passcode.") }

                Section {
                    TextField("Mac IP address", text: $manualHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                    TextField("Five-digit passcode", text: $manualPasscode)
                        .keyboardType(.numberPad)
                    TextField("This phone's name", text: $phoneName)
                    Button(isPairing ? "Pairing…" : "Pair") {
                        isPairing = true
                        store.pairManualWithPasscode(host: manualHost, portString: manualPort,
                                                     code: manualPasscode, phoneName: phoneName) { result in
                            isPairing = false
                            switch result {
                            case .success: dismiss()
                            case .failure(let error): pairingError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isPairing)
                } header: { Text("Manual address") }
                footer: { Text("Use the local address and actual port shown in Stats Companion when nearby discovery is unavailable.") }

                if store.selectedName != nil {
                    Section {
                        Button("Forget current Mac", role: .destructive) { store.forget() }
                    }
                }
            }
            .navigationTitle("Add Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Enter Mac passcode", isPresented: $showPasscodePrompt) {
                TextField("Five-digit passcode", text: $passcode)
                    .keyboardType(.numberPad)
                TextField("This phone's name", text: $phoneName)
                Button("Pair") {
                    guard let pairingDevice else { return }
                    isPairing = true
                    store.pairWithPasscode(pairingDevice, code: passcode, phoneName: phoneName) { result in
                        isPairing = false
                        switch result {
                        case .success: dismiss()
                        case .failure(let error): pairingError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The code appears in Pair new phone on the Mac.") }
            .alert("Pairing failed", isPresented: Binding(
                get: { pairingError != nil },
                set: { if !$0 { pairingError = nil } }
            )) {
                Button("OK") { pairingError = nil }
            } message: { Text(pairingError ?? "") }
        }
        .onAppear { store.startDiscovery() }
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
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
            HStack {
                Label("Network", systemImage: "network")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
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
