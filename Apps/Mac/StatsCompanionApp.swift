import ActivityCore
import AppKit
import Darwin
import ServiceManagement
import Security
import SwiftUI

@MainActor
final class StatsCompanionModel: ObservableObject {
    @Published private(set) var snapshot: MetricSnapshot
    @Published private(set) var localAddress: String?
    @Published private(set) var port: UInt16?
    @Published private(set) var isDiscoverable = false
    @Published private(set) var networkError: String?
    @Published private(set) var pairedPhones: [PairedPhone] = []
    @Published private(set) var pairingCode: String?
    @Published private(set) var pairingExpires: Date?
    @Published private(set) var pairingPending = false
    @Published var showingPairing = false
    @Published var updateMessage: String?
    @Published var checkingUpdates = false
    @Published var loginError: String?
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    private var recentSnapshots: [MetricSnapshot]
    private let sampler = SystemSampler()
    private var timer: Timer?
    private var server: MetricServer?

    init() {
        let oldKey: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ishtiaqsyed.StatsForIOS.setup",
            kSecAttrAccount as String: "local"
        ]
        SecItemDelete(oldKey as CFDictionary)
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

    func startPairing() {
        showingPairing = true
        guard pairingCode == nil, !pairingPending else { return }
        pairingPending = true
        server?.beginPairing { [weak self] code, expires in
            self?.pairingPending = false
            self?.pairingCode = code
            self?.pairingExpires = expires
        }
    }

    func revokePhone(_ id: UUID) {
        server?.revokePhone(id)
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            openAtLogin = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Approve Stats Companion in System Settings → General → Login Items."
                : nil
        } catch {
            openAtLogin = SMAppService.mainApp.status == .enabled
            loginError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        updateMessage = nil
        Task {
            defer { checkingUpdates = false }
            do {
                let url = URL(string: "https://api.github.com/repos/ishtiaq156/stats-for-ios/releases/latest")!
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("StatsCompanion", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    updateMessage = "Could not check for updates."
                    return
                }
                if response.statusCode == 404 {
                    updateMessage = "No releases have been published yet."
                    return
                }
                guard response.statusCode == 200 else {
                    updateMessage = "Update check failed (HTTP \(response.statusCode))."
                    return
                }
                struct Release: Decodable { let tag_name: String }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                updateMessage = latest.compare(current, options: .numeric) == .orderedDescending
                    ? "Version \(latest) is available on GitHub Releases."
                    : "Stats Companion \(current) is up to date."
            } catch {
                updateMessage = "Update check failed: \(error.localizedDescription)"
            }
        }
    }

    private func makeServer() -> MetricServer {
        MetricServer(snapshot: { [weak self] in
            self?.snapshot ?? MetricSnapshot(machineName: "Mac")
        }, history: { [weak self] in
            self?.recentSnapshots ?? []
        }, onPort: { [weak self] port in
            self?.port = port
            self?.localAddress = Self.ipv4Address().map { "\($0):\(port)" }
        }, onDiscovery: { [weak self] ready, error in
            self?.isDiscoverable = ready
            self?.networkError = error
        }, onPhones: { [weak self] phones in
            self?.pairedPhones = phones
        }, onPairingEnded: { [weak self] in
            self?.pairingCode = nil
            self?.pairingExpires = nil
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
            CompanionMenu(model: model)
        } label: {
            Label("Stats Companion", systemImage: "chart.xyaxis.line")
        }
        .menuBarExtraStyle(.window)
        Settings {
            CompanionSettings(model: model)
        }
    }
}

private struct CompanionMenu: View {
    @ObservedObject var model: StatsCompanionModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button(model.showingPairing ? "Hide pairing" : "Pair new phone") {
                if model.showingPairing { model.showingPairing = false }
                else { model.startPairing() }
            }
            .font(.headline)
            if model.showingPairing {
                if let code = model.pairingCode {
                    Text("Passcode").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(code).font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel("Copy passcode")
                    }
                    if let expires = model.pairingExpires {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("Expires in \(max(0, Int(expires.timeIntervalSince(context.date)))) seconds")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if model.pairingPending {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Create a new passcode") { model.startPairing() }
                }
            }
            Divider()
            Label {
                Text(networkStatus)
            } icon: {
                Image(systemName: model.isDiscoverable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(model.isDiscoverable ? .green : .yellow)
            }
            if model.pairedPhones.filter(\.isConnected).isEmpty {
                Label("No devices connected", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
            } else {
                ForEach(model.pairedPhones.filter(\.isConnected)) { phone in
                    Label(phone.name, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Divider()
            Button("Check for updates") { model.checkForUpdates() }
            if model.checkingUpdates { ProgressView().controlSize(.small) }
            if let message = model.updateMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                if message.contains("is available") {
                    Button("Open release") { open("https://github.com/ishtiaq156/stats-for-ios/releases/latest") }
                }
            }
            Button("Website") { open("https://github.com/ishtiaq156/stats-for-ios") }
            Button("About") { NSApp.orderFrontStandardAboutPanel(nil) }
            Divider()
            Button("Changelog") { open("https://github.com/ishtiaq156/stats-for-ios/releases") }
            Divider()
            Toggle("Open at login", isOn: Binding(
                get: { model.openAtLogin },
                set: { model.setOpenAtLogin($0) }
            ))
            if let error = model.loginError { Text(error).font(.caption).foregroundStyle(.red) }
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit Stats Companion") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.plain)
        .padding(18)
        .frame(width: 320)
    }

    private var networkStatus: String {
        if model.isDiscoverable, let port = model.port {
            return "Discoverable on the network using port \(port)"
        }
        return model.networkError ?? "Starting local discovery…"
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct CompanionSettings: View {
    @ObservedObject var model: StatsCompanionModel
    var body: some View {
        Form {
            Section("Network") {
                LabeledContent("Status", value: model.isDiscoverable ? "Discoverable" : (model.networkError ?? "Starting"))
                if let address = model.localAddress {
                    LabeledContent("Local address", value: address).textSelection(.enabled)
                }
            }
            Section("Paired phones") {
                if model.pairedPhones.isEmpty {
                    Text("No phones paired with a passcode yet.").foregroundStyle(.secondary)
                }
                ForEach(model.pairedPhones) { phone in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(phone.name)
                            Text(phone.lastSeen.map { "Last active \($0.formatted())" } ?? "Never active")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revoke") { model.revokePhone(phone.id) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 280)
    }
}
