import ActivityCore
import Foundation
import Network
import Security

@MainActor
final class NearbyMacStore: ObservableObject {
    struct Device: Identifiable {
        let endpoint: NWEndpoint
        let name: String
        var id: String { name }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var snapshot: MetricSnapshot?
    @Published private(set) var history: [MetricSnapshot] = []
    @Published private(set) var selectedName: String?
    @Published private(set) var status = "Looking for Macs"

    private let browser: NWBrowser
    private var selectedEndpoint: NWEndpoint?
    private var selectedKey: Data?
    private var timer: Timer?
    private var inFlight = false
    private var historyInFlight = false
    private var historyLoaded = false
    private var browsing = false
    private var selectionGeneration = UUID()
    private static let lastMacKey = "StatsForIOS.lastMac"
    private static let manualHostKey = "StatsForIOS.manualHost"
    private static let manualPortKey = "StatsForIOS.manualPort"

    init() {
        browser = NWBrowser(for: .bonjour(type: SecurePacket.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.devices = results.compactMap { result in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return Device(endpoint: result.endpoint, name: name)
                }.sorted { $0.name < $1.name }
                if let name = self.selectedName,
                   let device = self.devices.first(where: { $0.name == name }) {
                    self.selectedEndpoint = device.endpoint
                    self.refresh()
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.status = "Discovery failed: \(error.localizedDescription)" }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        restoreLastMac()
    }

    private func restoreLastMac() {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: Self.lastMacKey),
              let key = PairingStore.load(for: name) else { return }
        selectedName = name
        selectedKey = key
        status = "Looking for \(name)"
        if let host = defaults.string(forKey: Self.manualHostKey),
           let portNumber = defaults.object(forKey: Self.manualPortKey) as? Int,
           (1...65_535).contains(portNumber),
           let port = NWEndpoint.Port(rawValue: UInt16(portNumber)) {
            selectedEndpoint = .hostPort(host: .init(host), port: port)
            refresh()
        } else {
            startDiscovery()
        }
    }

    func startDiscovery() {
        guard !browsing else { return }
        browsing = true
        browser.start(queue: .main)
    }

    func pair(_ device: Device, keyString: String) -> Bool {
        guard let key = Data(base64Encoded: keyString.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.count == 32 else { return false }
        selectedName = device.name
        selectionGeneration = UUID()
        inFlight = false
        historyInFlight = false
        selectedEndpoint = device.endpoint
        selectedKey = key
        snapshot = nil
        history = []
        historyLoaded = false
        status = "Connecting"
        PairingStore.save(key, for: device.name)
        remember(device)
        refresh()
        return true
    }

    func pairManual(host: String, portString: String, keyString: String) -> Bool {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let number = UInt16(portString),
              let port = NWEndpoint.Port(rawValue: number) else { return false }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        let paired = pair(Device(endpoint: endpoint, name: "\(host):\(number)"), keyString: keyString)
        if paired {
            UserDefaults.standard.set(host, forKey: Self.manualHostKey)
            UserDefaults.standard.set(Int(number), forKey: Self.manualPortKey)
        }
        return paired
    }

    func select(_ device: Device) -> Bool {
        guard let key = PairingStore.load(for: device.name) else { return false }
        selectedName = device.name
        selectionGeneration = UUID()
        inFlight = false
        historyInFlight = false
        selectedEndpoint = device.endpoint
        selectedKey = key
        snapshot = nil
        history = []
        historyLoaded = false
        status = "Connecting"
        remember(device)
        refresh()
        return true
    }

    func forget() {
        if let selectedName { PairingStore.delete(for: selectedName) }
        selectedName = nil
        selectionGeneration = UUID()
        inFlight = false
        historyInFlight = false
        selectedEndpoint = nil
        selectedKey = nil
        snapshot = nil
        history = []
        historyLoaded = false
        status = "Looking for Macs"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.lastMacKey)
        defaults.removeObject(forKey: Self.manualHostKey)
        defaults.removeObject(forKey: Self.manualPortKey)
    }

    private func remember(_ device: Device) {
        let defaults = UserDefaults.standard
        defaults.set(device.name, forKey: Self.lastMacKey)
        if case let .hostPort(host, port) = device.endpoint {
            defaults.set(String(describing: host), forKey: Self.manualHostKey)
            defaults.set(Int(port.rawValue), forKey: Self.manualPortKey)
        } else {
            defaults.removeObject(forKey: Self.manualHostKey)
            defaults.removeObject(forKey: Self.manualPortKey)
        }
    }

    private func refresh() {
        guard !inFlight, let endpoint = selectedEndpoint, let key = selectedKey else { return }
        inFlight = true
        let generation = selectionGeneration
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state, on: connection, key: key, generation: generation) }
        }
        connection.start(queue: .main)
    }

    private func handle(_ state: NWConnection.State, on connection: NWConnection, key: Data, generation: UUID) {
            guard selectionGeneration == generation else { connection.cancel(); return }
            switch state {
            case .ready:
                guard let request = try? SecurePacket.seal(Data("snapshot.v1".utf8), using: key) else {
                    connection.cancel(); inFlight = false; return
                }
                connection.send(content: SecurePacket.frame(request), completion: .contentProcessed { error in
                    if error != nil {
                        connection.cancel()
                        Task { @MainActor in
                            if self.selectionGeneration == generation { self.fail() }
                        }
                    }
                })
                receiveHeader(on: connection, key: key, generation: generation)
            case .failed:
                connection.cancel()
                fail()
            default: break
            }
    }

    private func receiveHeader(on connection: NWConnection, key: Data, generation: UUID) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                guard self.selectionGeneration == generation else { connection.cancel(); return }
                guard error == nil, let data, let length = SecurePacket.length(data) else {
                    connection.cancel(); self.fail(); return
                }
                self.receiveBody(on: connection, key: key, length: length, generation: generation)
            }
        }
    }

    private func receiveBody(on connection: NWConnection, key: Data, length: Int, generation: UUID) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
            Task { @MainActor in
                defer { connection.cancel() }
                guard self?.selectionGeneration == generation else { return }
                guard error == nil, let body,
                      let plaintext = try? SecurePacket.open(body, using: key),
                      let snapshot = try? JSONDecoder().decode(MetricSnapshot.self, from: plaintext),
                      snapshot.version == MetricSnapshot.protocolVersion else {
                    self?.fail(); return
                }
                self?.snapshot = snapshot
                self?.append(snapshot)
                self?.status = "Last update \(snapshot.timestamp.formatted(date: .omitted, time: .standard))"
                self?.inFlight = false
                if self?.historyLoaded == false { self?.fetchHistory() }
            }
        }
    }

    private func fail() {
        inFlight = false
        if let snapshot {
            status = "Disconnected · last update \(snapshot.timestamp.formatted(date: .omitted, time: .standard))"
        } else {
            status = "Cannot connect · check setup key"
        }
    }

    private func append(_ sample: MetricSnapshot) {
        guard sample.version == MetricSnapshot.protocolVersion else { return }
        if history.last?.timestamp != sample.timestamp { history.append(sample) }
        if history.count > 900 { history.removeFirst(history.count - 900) }
    }

    private func fetchHistory() {
        guard !historyInFlight, let endpoint = selectedEndpoint, let key = selectedKey else { return }
        historyInFlight = true
        let generation = selectionGeneration
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                guard self.selectionGeneration == generation else { connection.cancel(); return }
                switch state {
                case .ready:
                    guard let request = try? SecurePacket.seal(Data("history.v1".utf8), using: key) else {
                        connection.cancel(); self.historyInFlight = false; return
                    }
                    connection.send(content: SecurePacket.frame(request), completion: .contentProcessed { error in
                        if error != nil {
                            connection.cancel()
                            Task { @MainActor in
                                if self.selectionGeneration == generation { self.historyInFlight = false }
                            }
                        }
                    })
                    self.receiveHistoryHeader(on: connection, key: key, generation: generation)
                case .failed:
                    connection.cancel()
                    self.historyInFlight = false
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func receiveHistoryHeader(on connection: NWConnection, key: Data, generation: UUID) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard self?.selectionGeneration == generation else { connection.cancel(); return }
                guard error == nil, let data, let length = SecurePacket.length(data) else {
                    connection.cancel(); self?.historyInFlight = false; return
                }
                self?.receiveHistoryBody(on: connection, key: key, length: length, generation: generation)
            }
        }
    }

    private func receiveHistoryBody(on connection: NWConnection, key: Data, length: Int, generation: UUID) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
            Task { @MainActor in
                defer { connection.cancel() }
                guard self?.selectionGeneration == generation else { return }
                self?.historyInFlight = false
                guard error == nil, let body,
                      let plaintext = try? SecurePacket.open(body, using: key),
                      let samples = try? JSONDecoder().decode([MetricSnapshot].self, from: plaintext) else { return }
                self?.mergeHistory(samples)
                self?.historyLoaded = true
            }
        }
    }

    private func mergeHistory(_ samples: [MetricSnapshot]) {
        let valid = (history + samples).filter {
            $0.version == MetricSnapshot.protocolVersion && $0.timestamp > Date().addingTimeInterval(-31 * 60)
        }
        history = Array(Dictionary(valid.map { ($0.timestamp, $0) }, uniquingKeysWith: { latest, _ in latest })
            .values.sorted { $0.timestamp < $1.timestamp }.suffix(900))
    }
}

private enum PairingStore {
    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.ishtiaqsyed.StatsForIOS.pairing",
         kSecAttrAccount as String: name]
    }

    static func save(_ key: Data, for name: String) {
        let base = query(name)
        SecItemDelete(base as CFDictionary)
        var values = base
        values[kSecValueData as String] = key
        SecItemAdd(values as CFDictionary, nil)
    }

    static func load(for name: String) -> Data? {
        var values = query(name)
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(values as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(for name: String) { SecItemDelete(query(name) as CFDictionary) }
}
