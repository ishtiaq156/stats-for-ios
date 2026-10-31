import ActivityCore
import Foundation
import Network
import Security

final class MetricServer: NSObject, NetServiceDelegate {
    enum PairingEndReason {
        case used
        case expired
        case exhausted
    }

    private let snapshot: () -> MetricSnapshot
    private let history: () -> [MetricSnapshot]
    private let onPort: (UInt16) -> Void
    private let onDiscovery: (Bool, String?) -> Void
    private let onPhones: ([PairedPhone]) -> Void
    private let onPairingEnded: (PairingEndReason) -> Void
    private let queue = DispatchQueue(label: "StatsForIOS.MetricServer")
    private var listener: NWListener?
    private var advertiser: NetService?
    private var attemptedFallback = false
    private let phones: PhoneRegistry
    private struct PairingSession {
        let id: UUID
        let code: String
        let expires: Date
        var attempts = 0
        var handshake: UUID?
    }
    private var pairingSession: PairingSession?

    init(snapshot: @escaping () -> MetricSnapshot,
         history: @escaping () -> [MetricSnapshot],
         onPort: @escaping (UInt16) -> Void,
         onDiscovery: @escaping (Bool, String?) -> Void,
         onPhones: @escaping ([PairedPhone]) -> Void,
         onPairingEnded: @escaping (PairingEndReason) -> Void,
         phones: PhoneRegistry = PhoneRegistry()) {
        self.snapshot = snapshot
        self.history = history
        self.onPort = onPort
        self.onDiscovery = onDiscovery
        self.onPhones = onPhones
        self.onPairingEnded = onPairingEnded
        self.phones = phones
        super.init()
    }

    func start() {
        startListener(preferredPort: NWEndpoint.Port(rawValue: 8888)!)
        queue.async { [weak self] in
            guard let self else { return }
            self.publishPhones()
        }
    }

    func beginPairing(completion: @escaping (String, Date) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var random: UInt32 = 0
            let previousCode = self.pairingSession?.code
            var code: String
            repeat {
                guard SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &random) == errSecSuccess else { return }
                code = String(format: "%05d", random % 100_000)
            } while code == previousCode
            let session = PairingSession(id: UUID(), code: code, expires: Date().addingTimeInterval(300))
            self.pairingSession = session
            DispatchQueue.main.async { completion(code, session.expires) }
            self.queue.asyncAfter(deadline: .now() + 300) { [weak self] in
                guard let self, self.pairingSession?.id == session.id else { return }
                self.endPairing(reason: .expired)
            }
        }
    }

    func revokePhone(_ id: UUID) {
        queue.async { [weak self] in
            self?.phones.revoke(id)
            self?.publishPhones()
        }
    }

    private func startListener(preferredPort: NWEndpoint.Port?) {
        do {
            let listener: NWListener
            if let preferredPort {
                listener = try NWListener(using: .tcp, on: preferredPort)
            } else {
                listener = try NWListener(using: .tcp)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                NSLog("Stats Companion listener: %@", String(describing: state))
                if case .ready = state, let port = listener?.port {
                    DispatchQueue.main.async {
                        self?.onPort(port.rawValue)
                        self?.advertise(port: port)
                    }
                } else if case .failed(let error) = state {
                    guard let self else { return }
                    if !self.attemptedFallback, preferredPort != nil {
                        self.attemptedFallback = true
                        listener?.cancel()
                        self.startListener(preferredPort: nil)
                    } else {
                        DispatchQueue.main.async { self.onDiscovery(false, error.localizedDescription) }
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            if !attemptedFallback, preferredPort != nil {
                attemptedFallback = true
                startListener(preferredPort: nil)
            } else {
                DispatchQueue.main.async { [onDiscovery] in onDiscovery(false, error.localizedDescription) }
            }
        }
    }

    func stop() {
        listener?.cancel()
        advertiser?.stop()
        advertiser = nil
        queue.async { [weak self] in self?.pairingSession = nil }
    }

    private func advertise(port: NWEndpoint.Port) {
        advertiser?.stop()
        let service = NetService(domain: "local.", type: SecurePacket.serviceType + ".", name: "Stats Companion", port: Int32(port.rawValue))
        let computerName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        service.setTXTRecord(NetService.data(fromTXTRecord: ["name": Data(computerName.utf8)]))
        service.delegate = self
        service.publish()
        advertiser = service
    }

    func netServiceDidPublish(_ sender: NetService) {
        NSLog("Stats Companion Bonjour published")
        onDiscovery(true, nil)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        NSLog("Stats Companion Bonjour failed: %@", String(describing: errorDict))
        onDiscovery(false, "Local discovery is unavailable. Manual address pairing may still work.")
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
            guard let self, error == nil, let data else {
                connection.cancel()
                return
            }
            if data.starts(with: PairingWire.helloPrefix) {
                self.handlePairingHello(data.dropFirst(PairingWire.helloPrefix.count), on: connection)
                return
            }
            let prefixLength = PairingWire.requestPrefix.count
            guard data.starts(with: PairingWire.requestPrefix),
                  data.count > prefixLength + 36,
                  let idString = String(data: data[prefixLength..<(prefixLength + 36)], encoding: .utf8),
                  let phoneID = UUID(uuidString: idString),
                  let key = self.phones.key(for: phoneID) else {
                connection.cancel()
                return
            }
            let encrypted = Data(data.dropFirst(prefixLength + 36))
            guard let request = try? SecurePacket.open(encrypted, using: key),
                  let command = String(data: request, encoding: .utf8),
                  command == "snapshot.v1" || command == "history.v1" else {
                connection.cancel()
                return
            }
            self.phones.recordActivity(for: phoneID)
            self.publishPhones()
            DispatchQueue.main.async {
                let payload: Data?
                if command == "history.v1" {
                    payload = try? JSONEncoder().encode(self.history())
                } else {
                    payload = try? JSONEncoder().encode(self.snapshot())
                }
                guard let payload,
                      let encrypted = try? SecurePacket.seal(payload, using: key) else {
                    connection.cancel()
                    return
                }
                connection.send(content: SecurePacket.frame(encrypted), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func handlePairingHello(_ body: Data, on connection: NWConnection) {
        guard var session = pairingSession, session.expires > Date(),
              session.attempts < 3, session.handshake == nil else {
            connection.cancel()
            return
        }
        session.attempts += 1
        let handshake = UUID()
        session.handshake = handshake
        pairingSession = session
        guard let hello = try? JSONDecoder().decode(PairingWire.Hello.self, from: body),
              hello.message.count == 33,
              let exchange = try? PairingExchange(role: .mac, code: session.code),
              let sessionKey = try? exchange.finish(peerMessage: hello.message) else {
            failPairingAttempt(handshake)
            connection.cancel()
            return
        }
        let response = PairingWire.helloPrefix + exchange.message
        connection.send(content: SecurePacket.frame(response), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                self?.failPairingAttempt(handshake)
                connection.cancel()
                return
            }
            self.receiveFrame(on: connection) { [weak self] body in
                guard let self, self.pairingSession?.handshake == handshake,
                      (self.pairingSession?.expires ?? .distantPast) > Date(),
                      let body,
                      let opened = try? SecurePacket.open(body, using: sessionKey),
                      let claim = try? JSONDecoder().decode(PairingWire.Claim.self, from: opened),
                      !claim.phoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      claim.phoneName.count <= 60 else {
                    self?.failPairingAttempt(handshake)
                    connection.cancel()
                    return
                }
                var credential = Data(count: 32)
                let status = credential.withUnsafeMutableBytes {
                    SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
                }
                guard status == errSecSuccess,
                      let id = self.phones.enroll(name: claim.phoneName, key: credential),
                      let enrollment = try? JSONEncoder().encode(PairingWire.Enrollment(phoneID: id, credential: credential)),
                      let sealed = try? SecurePacket.seal(enrollment, using: sessionKey) else {
                    self.failPairingAttempt(handshake)
                    connection.cancel()
                    return
                }
                self.endPairing(reason: .used)
                self.publishPhones()
                connection.send(content: SecurePacket.frame(sealed), completion: .contentProcessed { _ in connection.cancel() })
            }
        })
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in
            guard let self, self.pairingSession?.handshake == handshake else { return }
            self.failPairingAttempt(handshake)
            connection?.cancel()
        }
    }

    private func receiveFrame(on connection: NWConnection, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, let length = SecurePacket.length(header) else {
                completion(nil)
                return
            }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                completion(error == nil ? body : nil)
            }
        }
    }

    private func failPairingAttempt(_ id: UUID) {
        guard var session = pairingSession, session.handshake == id else { return }
        if session.attempts >= 3 {
            endPairing(reason: .exhausted)
        } else if session.expires <= Date() {
            endPairing(reason: .expired)
        } else {
            session.handshake = nil
            pairingSession = session
        }
    }

    private func endPairing(reason: PairingEndReason) {
        pairingSession = nil
        DispatchQueue.main.async { [onPairingEnded] in onPairingEnded(reason) }
    }

    private func publishPhones() {
        let list = phones.all()
        DispatchQueue.main.async { [onPhones] in onPhones(list) }
    }

}
