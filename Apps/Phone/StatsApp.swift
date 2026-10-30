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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum ConnectionState {
        case preview, connecting, online, offline
    }

    private var connectionState: ConnectionState {
        guard nearby.selectedName != nil else { return .preview }
        if nearby.status.hasPrefix("Disconnected") || nearby.status.hasPrefix("Cannot connect") {
            return .offline
        }
        if nearby.snapshot != nil, nearby.status.hasPrefix("Last update") { return .online }
        return .connecting
    }

    private var displayed: MetricSnapshot {
        nearby.snapshot ?? (nearby.selectedName == nil
            ? preview.snapshot : MetricSnapshot(machineName: nearby.selectedName ?? "Mac"))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    deviceHeader
                    if nearby.selectedName == nil {
                        pairingPrompt
                    } else {
                        connectionStatus
                    }

                    Text(nearby.selectedName == nil ? "Sample dashboard" : "System activity")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: metricColumns, spacing: 12) {
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
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 12) {
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
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPairing = true } label: {
                        Image(systemName: nearby.selectedName == nil ? "plus.circle" : "desktopcomputer.and.arrow.down")
                    }
                    .accessibilityLabel(nearby.selectedName == nil ? "Add Mac" : "Manage Macs")
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

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
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
                .font(.title3.weight(.medium))
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(nearby.selectedName ?? "Your Mac")
                    .font(.headline)
                Text(nearby.selectedName == nil ? "No Mac connected" : connectionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if nearby.selectedName != nil {
                Button("Change") { showPairing = true }
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(16)
        .statsCardBackground()
    }

    private var connectionTitle: String {
        switch connectionState {
        case .preview: "Sample readings"
        case .connecting: "Connecting…"
        case .online: "Receiving live readings"
        case .offline: "Connection unavailable"
        }
    }

    private var connectionStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: connectionState == .online ? "checkmark.circle.fill" :
                    connectionState == .offline ? "exclamationmark.circle.fill" : "arrow.triangle.2.circlepath")
                .foregroundStyle(connectionState == .online ? Color.green :
                                 connectionState == .offline ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            Text(nearby.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var pairingPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("See your Mac at a glance")
                .font(.headline)
            Text("Pair with Stats Companion on the same network to see live CPU, memory, storage, and network activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { showPairing = true } label: {
                Label("Connect a Mac", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("The readings below are examples.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .statsCardBackground()
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
    @State private var showManualAddress = false
    @State private var showForgetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.devices.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(store.status.hasPrefix("Discovery failed") ? "Nearby search unavailable" : "Searching for Macs",
                                  systemImage: store.status.hasPrefix("Discovery failed") ? "wifi.exclamationmark" : "magnifyingglass")
                                .font(.headline)
                            Text(store.status.hasPrefix("Discovery failed")
                                 ? "You can still connect using the Mac's local IP address and port below."
                                 : "Open Stats Companion on your Mac. Both devices need to be on the same network.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
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
                                .disabled(isPairing)
                                Spacer()
                                if store.hasSavedPairing(device) {
                                    Button("Pair again") {
                                        pairingDevice = device
                                        passcode = ""
                                        showPasscodePrompt = true
                                    }
                                    .font(.caption)
                                    .disabled(isPairing)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: { Text("Nearby Macs") }
                footer: { Text("Enter the five-digit passcode displayed at the top of the Stats Companion menu on your Mac.") }

                Section {
                    DisclosureGroup("Connect using IP address", isExpanded: $showManualAddress) {
                        TextField("Mac IP address", text: $manualHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Port", text: $manualPort)
                            .keyboardType(.numberPad)
                        SecureField("Five-digit passcode", text: $manualPasscode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        TextField("This phone's name", text: $phoneName)
                        Button {
                            isPairing = true
                            store.pairManualWithPasscode(host: manualHost, portString: manualPort,
                                                         code: manualPasscode, phoneName: phoneName) { result in
                                isPairing = false
                                switch result {
                                case .success: dismiss()
                                case .failure(let error): pairingError = error.localizedDescription
                                }
                            }
                        } label: {
                            if isPairing {
                                ProgressView("Pairing…")
                            } else {
                                Text("Pair with address")
                            }
                        }
                        .disabled(isPairing || manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || UInt16(manualPort) == nil || manualPasscode.count != 5)
                    }
                } header: { Text("Manual address") }
                footer: { Text("If your Mac isn't discovered, enter the local address and port shown in Stats Companion.") }

                if store.selectedName != nil {
                    Section {
                        Button("Forget current Mac", role: .destructive) {
                            showForgetConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle("Mac connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Enter Mac passcode", isPresented: $showPasscodePrompt) {
                TextField("Five-digit passcode", text: $passcode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
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
            } message: { Text("The code appears at the top of the Stats Companion menu on your Mac.") }
            .alert("Pairing failed", isPresented: Binding(
                get: { pairingError != nil },
                set: { if !$0 { pairingError = nil } }
            )) {
                Button("OK") { pairingError = nil }
            } message: { Text(pairingError ?? "") }
            .confirmationDialog("Forget this Mac?", isPresented: $showForgetConfirmation,
                                titleVisibility: .visible) {
                Button("Forget Mac", role: .destructive) {
                    store.forget()
                    dismiss()
                }
            } message: {
                Text("You will need to pair again to see this Mac's stats.")
            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if let fraction {
                GeometryReader { proxy in
                    Capsule().fill(tint.opacity(0.13))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint)
                                .frame(width: proxy.size.width * min(1, max(0, fraction)))
                        }
                }
                .frame(height: 5)
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 175, alignment: .topLeading)
        .statsCardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Show \(title.lowercased()) details")
    }
}

private struct NetworkCard: View {
    let snapshot: MetricSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text("Network")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "network")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(width: 34, height: 34)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 16) {
                rate("Download", icon: "arrow.down", value: snapshot.networkReceivedBytesPerSecond)
                Divider()
                rate("Upload", icon: "arrow.up", value: snapshot.networkSentBytesPerSecond)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsCardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Show network details")
    }

    private func rate(_ name: String, icon: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(name, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(MetricFormat.rate(value))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.65).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func statsCardBackground() -> some View {
        self
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
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
