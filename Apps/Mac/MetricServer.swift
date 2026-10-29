import ActivityCore
import Foundation
import Network
import Security

final class MetricServer: NSObject, NetServiceDelegate {
    let setupKey: Data
    private let snapshot: () -> MetricSnapshot
    private let onPort: (UInt16) -> Void
    private let queue = DispatchQueue(label: "MacActivity.MetricServer")
    private var listener: NWListener?
    private var advertiser: NetService?

    init(snapshot: @escaping () -> MetricSnapshot, onPort: @escaping (UInt16) -> Void) {
        self.snapshot = snapshot
        self.onPort = onPort
        self.setupKey = Self.loadOrCreateKey()
        super.init()
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                NSLog("Stats Companion listener: %@", String(describing: state))
                if case .ready = state, let port = listener?.port {
                    DispatchQueue.main.async {
                        self?.onPort(port.rawValue)
                        self?.advertise(port: port)
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Stats Companion listener failed: %@", String(describing: error))
        }
    }

    func stop() {
        listener?.cancel()
        advertiser?.stop()
    }

    private func advertise(port: NWEndpoint.Port) {
        advertiser?.stop()
        let service = NetService(domain: "local.", type: SecurePacket.serviceType + ".", name: "Stats Companion", port: Int32(port.rawValue))
        service.delegate = self
        service.publish()
        advertiser = service
    }

    func netServiceDidPublish(_ sender: NetService) {
        NSLog("Stats Companion Bonjour published")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        NSLog("Stats Companion Bonjour failed: %@", String(describing: errorDict))
    }

    static func revokeAllPhones() {
        SecItemDelete(keyQuery() as CFDictionary)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeader(on: connection)
    }

    private func receiveHeader(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, let length = SecurePacket.length(data) else {
                connection.cancel()
                return
            }
            self.receiveBody(on: connection, length: length)
        }
    }

    private func receiveBody(on connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self, error == nil, let data,
                  let request = try? SecurePacket.open(data, using: self.setupKey),
                  request == Data("snapshot.v1".utf8) else {
                connection.cancel()
                return
            }
            DispatchQueue.main.async {
                guard let payload = try? JSONEncoder().encode(self.snapshot()),
                      let encrypted = try? SecurePacket.seal(payload, using: self.setupKey) else {
                    connection.cancel()
                    return
                }
                connection.send(content: SecurePacket.frame(encrypted), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private static func loadOrCreateKey() -> Data {
        var query = keyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let key = item as? Data, key.count == 32 { return key }

        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        precondition(status == errSecSuccess, "Cannot create secure setup key")
        var add = keyQuery()
        add[kSecValueData as String] = key
        precondition(SecItemAdd(add as CFDictionary, nil) == errSecSuccess, "Cannot save setup key")
        return key
    }

    private static func keyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ishtiaqsyed.MacActivity.setup",
            kSecAttrAccount as String: "local"
        ]
    }
}
