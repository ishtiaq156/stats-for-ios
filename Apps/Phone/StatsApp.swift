import ActivityCore
import SwiftUI

@main
struct StatsApp: App {
    var body: some Scene {
        WindowGroup { PhoneRootView() }
    }
}

private struct PhoneRootView: View {
    @StateObject private var nearby = NearbyMacStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if nearby.selectedName != nil {
                    NearbyMacsView(store: nearby)
                } else {
                    WelcomeFlowView(store: nearby)
                }
            }
            .navigationTitle("Nearby Macs")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: Binding(
                get: { nearby.sessionActive },
                set: { if !$0 { nearby.endSession() } }
            )) {
                OverviewView(nearby: nearby)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: nearby.suspendForBackground()
            case .active: nearby.resumeFromBackground()
            default: break
            }
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var nearby: NearbyMacStore
    @State private var showSettings = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var displayed: MetricSnapshot {
        nearby.snapshot ?? MetricSnapshot(machineName: nearby.selectedDisplayName ?? "Mac")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("System activity")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    NavigationLink {
                        MetricDetailView(kind: .cpu, store: nearby)
                    } label: {
                        MetricCard(title: "CPU", icon: "cpu", tint: .orange,
                                   value: MetricFormat.percent(displayed.cpuFraction),
                                   detail: "Processor load", fraction: displayed.cpuFraction)
                    }
                    NavigationLink {
                        MetricDetailView(kind: .memory, store: nearby)
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
                        MetricDetailView(kind: .storage, store: nearby)
                    } label: {
                        MetricCard(title: "Storage", icon: "internaldrive", tint: .blue,
                                   value: MetricFormat.bytes(displayed.diskFreeBytes),
                                   detail: "free of \(MetricFormat.bytes(displayed.diskTotalBytes))",
                                   fraction: diskUsedFraction(displayed))
                    }
                    NavigationLink {
                        MetricDetailView(kind: .network, store: nearby)
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
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Dashboard settings")
            }
        }
        .sheet(isPresented: $showSettings) { DashboardSettingsView(nearby: nearby) }
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

}

private struct DashboardSettingsView: View {
    @ObservedObject var nearby: NearbyMacStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Dashboard") {
                    Picker("Refresh interval", selection: Binding(
                        get: { nearby.refreshIntervalSeconds },
                        set: { nearby.setRefreshInterval($0) }
                    )) {
                        ForEach(NearbyMacStore.refreshIntervals, id: \.self) { seconds in
                            Text("\(seconds) seconds").tag(seconds)
                        }
                    }
                }
                Section {
                    Button("About This Mac") { showAbout = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAbout) { AboutThisMacView(store: nearby) }
        }
    }
}

private struct AboutThisMacView: View {
    @ObservedObject var store: NearbyMacStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Button { dismiss() } label: {
                        Circle().fill(Color(red: 1, green: 0.38, blue: 0.35))
                            .frame(width: 13, height: 13)
                    }
                    .accessibilityLabel("Close About This Mac")
                    Circle().fill(Color(white: 0.88)).frame(width: 13, height: 13)
                    Circle().fill(Color(white: 0.88)).frame(width: 13, height: 13)
                    Spacer()
                }
                .padding(.top, 24)

                if let info = store.aboutInfo {
                    if let data = info.imagePNG, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(width: 220, height: 170)
                            .padding(.top, 30)
                    } else {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 100, weight: .ultraLight))
                            .frame(height: 170)
                            .padding(.top, 30)
                    }
                    Text(info.modelName)
                        .font(.system(size: 26, weight: .semibold))
                        .padding(.top, 16)
                    if let chip = info.chip {
                        Text(chip.replacingOccurrences(of: "Apple ", with: ""))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(.top, 3)
                    }
                    VStack(spacing: 5) {
                        aboutRow("Chip", info.chip)
                        aboutRow("Memory", info.memory)
                        aboutRow("Startup disk", info.startupDisk)
                        aboutRow("Serial number", info.serialNumber)
                        aboutRow("macOS", info.macOS)
                    }
                    .padding(.top, 28)
                    Text("™ and © 1983–2026 Apple Inc.\nAll Rights Reserved.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 36)
                } else if let error = store.aboutError {
                    ContentUnavailableView("About This Mac unavailable", systemImage: "desktopcomputer.trianglebadge.exclamationmark", description: Text(error))
                        .padding(.top, 80)
                    Button("Try Again") { store.loadAbout() }
                        .padding(.top, 12)
                } else {
                    ProgressView("Loading Mac details…")
                        .padding(.top, 160)
                }
                Spacer(minLength: 30)
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .presentationDetents([.height(580), .large])
        .presentationDragIndicator(.hidden)
        .task { store.loadAbout() }
    }

    private func aboutRow(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).frame(width: 100, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(value ?? "—").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
    }
}

struct PairingView: View {
    @ObservedObject var store: NearbyMacStore
    @Environment(\.dismiss) private var dismiss
    @State private var pairingDevice: NearbyMacStore.Device?
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
                            Label(store.discoveryError != nil ? "Nearby search unavailable" : "Searching for Macs",
                                  systemImage: store.discoveryError != nil ? "wifi.exclamationmark" : "magnifyingglass")
                                .font(.headline)
                            Text(store.discoveryError != nil
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
                                    }
                                } label: {
                                    Label(store.displayName(for: device), systemImage: "desktopcomputer")
                                }
                                .disabled(isPairing)
                                Spacer()
                                if store.hasSavedPairing(device) {
                                    Button("Pair again") {
                                        pairingDevice = device
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
            .sheet(item: $pairingDevice) { device in
                PasscodeEntryView(device: device, store: store) { dismiss() }
            }
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
