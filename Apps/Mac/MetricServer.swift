import ActivityCore
import Foundation
import Network
import Security

final class MetricServer {
    let setupKey: Data
    private let snapshot: () -> MetricSnapshot
    private let queue = DispatchQueue(label: "MacActivity.MetricServer")
    private var listener: NWListener?

    init(snapshot: @escaping () -> MetricSnapshot) {
        self.snapshot = snapshot
        self.setupKey = Self.loadOrCreateKey()
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = .init(name: Host.current().localizedName ?? "Mac", type: SecurePacket.serviceType)
            listener.stateUpdateHandler = { state in
                NSLog("Mac Activity listener: %@", String(describing: state))
            }
            listener.serviceRegistrationUpdateHandler = { change in
                NSLog("Mac Activity Bonjour: %@", String(describing: change))
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Mac Activity listener failed: %@", String(describing: error))
        }
    }

    func stop() { listener?.cancel() }

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
