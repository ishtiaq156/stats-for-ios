import ActivityCore
import AppKit
import Darwin
import ServiceManagement
import Security
import SwiftUI

enum CompanionSettingsPage: Equatable {
    case home
    case changelog
}
enum CompanionUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed(String)
}

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
    @Published private(set) var pairingLocked = false
    @Published private(set) var updateState: CompanionUpdateState = .idle
    @Published var loginError: String?
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var menuBarVisible = true
    @Published private(set) var dockVisible = false
    @Published var settingsPage: CompanionSettingsPage = .home
    @Published var visibilityError: String?
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
        let defaults = UserDefaults.standard
        dockVisible = defaults.bool(forKey: "StatsCompanion.showDock")
        menuBarVisible = defaults.object(forKey: "StatsCompanion.showMenuBar") as? Bool ?? true
        if !dockVisible && !menuBarVisible { menuBarVisible = true }
        server = makeServer()
        server?.start()
        startPairing()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            _ = NSApp.setActivationPolicy(self.dockVisible ? .regular : .accessory)
            Self.installDockIcon()
        }
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
        guard pairingCode == nil, !pairingPending, !pairingLocked else { return }
        pairingPending = true
        server?.beginPairing { [weak self] code, expires in
            self?.pairingPending = false
            self?.pairingCode = code
            self?.pairingExpires = expires
        }
    }

    func refreshPasscode() {
        guard !pairingPending else { return }
        // Keep the current passcode on screen until the replacement is ready.
        // Clearing it here briefly renders the "Generating passcode" layout
        // in both the status menu and Settings, making the interface jump.
        pairingPending = true
        server?.beginPairing { [weak self] code, expires in
            guard let self else { return }
            self.pairingCode = code
            self.pairingExpires = expires
            self.pairingLocked = false
            self.pairingPending = false
        }
    }

    func setMenuBarVisible(_ enabled: Bool) {
        guard enabled || dockVisible else { return }
        guard menuBarVisible != enabled else { return }
        menuBarVisible = enabled
        UserDefaults.standard.set(enabled, forKey: "StatsCompanion.showMenuBar")
    }

    func setDockVisible(_ enabled: Bool) {
        guard enabled || menuBarVisible else { return }
        if NSApp.setActivationPolicy(enabled ? .regular : .accessory) {
            dockVisible = enabled
            visibilityError = nil
            UserDefaults.standard.set(enabled, forKey: "StatsCompanion.showDock")
            if enabled {
                // Reassign after the Dock activation policy changes, since
                // AppKit may recreate the tile when switching to .regular.
                Self.installDockIcon()
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            visibilityError = "Could not change Dock visibility."
        }
    }

    private static func installDockIcon() {
        // A menu-bar-only launch can leave AppKit with its generic icon when
        // the user later enables the Dock. Load the compiled icon explicitly.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        } else if let brandMark = NSImage(named: "StatsBrandMark") {
            // The About artwork remains a useful fallback for development
            // bundles that have not packaged the .icns yet.
            NSApp.applicationIconImage = brandMark
        }
        NSApp.dockTile.display()
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
        guard updateState != .checking else { return }
        updateState = .checking
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/ishtiaq156/stats-for-ios/releases/latest")!
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("StatsCompanion", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    updateState = .failed("Could not check for updates")
                    return
                }
                if response.statusCode == 404 {
                    showUpToDate()
                    return
                }
                guard response.statusCode == 200 else {
                    updateState = .failed("Update check failed (HTTP \(response.statusCode))")
                    return
                }
                struct Release: Decodable {
                    let tag_name: String
                    let html_url: URL
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if latest.compare(current, options: .numeric) == .orderedDescending,
                   release.html_url.host == "github.com" {
                    updateState = .available(version: latest, url: release.html_url)
                } else {
                    showUpToDate()
                }
            } catch {
                updateState = .failed("Update check failed")
            }
        }
    }

    private func showUpToDate() {
        updateState = .upToDate
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if updateState == .upToDate { updateState = .idle }
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
        }, onPairingEnded: { [weak self] reason in
            guard let self else { return }
            switch reason {
            case .exhausted:
                self.pairingCode = nil
                self.pairingExpires = nil
                self.pairingLocked = true
            case .expired, .used:
                // Automatic rotation uses the same uninterrupted UI update
                // as tapping Refresh. Only the exhausted state hides the code.
                self.refreshPasscode()
            }
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
        MenuBarExtra(isInserted: Binding(
            get: { model.menuBarVisible },
            set: { model.setMenuBarVisible($0) }
        )) {
            CompanionMenu(model: model)
        } label: {
            Image("StatsStatusMark")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: 18, height: 18)
                .accessibilityLabel("Stats Companion")
        }
        .menuBarExtraStyle(.window)
        Settings {
            CompanionSettings(model: model)
        }
        #if DEBUG
        WindowGroup("Settings Preview") {
            if ProcessInfo.processInfo.environment["STATS_UI_PREVIEW"] == "1" {
                CompanionSettings(model: model)
            } else {
                EmptyView()
            }
        }
        #endif
    }
}
