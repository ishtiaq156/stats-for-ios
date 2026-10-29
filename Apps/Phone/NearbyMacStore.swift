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
    @Published private(set) var selectedName: String?
    @Published private(set) var status = "Looking for Macs"

    private let browser: NWBrowser
    private var selectedEndpoint: NWEndpoint?
    private var selectedKey: Data?
    private var timer: Timer?
    private var inFlight = false

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
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.status = "Discovery failed: \(error.localizedDescription)" }
            }
        }
        browser.start(queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func pair(_ device: Device, keyString: String) -> Bool {
        guard let key = Data(base64Encoded: keyString.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.count == 32 else { return false }
        selectedName = device.name
        selectedEndpoint = device.endpoint
        selectedKey = key
        snapshot = nil
        status = "Connecting"
        PairingStore.save(key, for: device.name)
        refresh()
        return true
    }

    func pairManual(host: String, portString: String, keyString: String) -> Bool {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let number = UInt16(portString),
              let port = NWEndpoint.Port(rawValue: number) else { return false }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        return pair(Device(endpoint: endpoint, name: "\(host):\(number)"), keyString: keyString)
    }

    func select(_ device: Device) -> Bool {
        guard let key = PairingStore.load(for: device.name) else { return false }
        selectedName = device.name
        selectedEndpoint = device.endpoint
        selectedKey = key
        snapshot = nil
        status = "Connecting"
        refresh()
        return true
    }

    func forget() {
        if let selectedName { PairingStore.delete(for: selectedName) }
        selectedName = nil
        selectedEndpoint = nil
        selectedKey = nil
        snapshot = nil
        status = "Looking for Macs"
    }

    private func refresh() {
        guard !inFlight, let endpoint = selectedEndpoint, let key = selectedKey else { return }
        inFlight = true
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state, on: connection, key: key) }
        }
        connection.start(queue: .main)
    }

    private func handle(_ state: NWConnection.State, on connection: NWConnection, key: Data) {
            switch state {
            case .ready:
                guard let request = try? SecurePacket.seal(Data("snapshot.v1".utf8), using: key) else {
                    connection.cancel(); inFlight = false; return
                }
                connection.send(content: SecurePacket.frame(request), completion: .contentProcessed { error in
                    if error != nil {
                        connection.cancel()
                        Task { @MainActor in self.fail() }
                    }
                })
                receiveHeader(on: connection, key: key)
            case .failed:
                connection.cancel()
                fail()
            default: break
            }
    }

    private func receiveHeader(on connection: NWConnection, key: Data) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                guard error == nil, let data, let length = SecurePacket.length(data) else {
                    connection.cancel(); self.fail(); return
                }
                self.receiveBody(on: connection, key: key, length: length)
            }
        }
    }

    private func receiveBody(on connection: NWConnection, key: Data, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
            Task { @MainActor in
                defer { connection.cancel() }
                guard error == nil, let body,
                      let plaintext = try? SecurePacket.open(body, using: key),
                      let snapshot = try? JSONDecoder().decode(MetricSnapshot.self, from: plaintext),
                      snapshot.version == MetricSnapshot.protocolVersion else {
                    self?.fail(); return
                }
                self?.snapshot = snapshot
                self?.status = "Updated just now"
                self?.inFlight = false
            }
        }
    }

    private func fail() {
        inFlight = false
        status = snapshot == nil ? "Cannot connect · check setup key" : "Disconnected · showing last update"
    }
}

private enum PairingStore {
    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.ishtiaqsyed.MacActivity.pairing",
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
