import Foundation
import Network

/// A connected browser extension instance (one per browser profile).
final class BridgeClient {
    fileprivate let connection: NWConnection

    fileprivate init(connection: NWConnection) {
        self.connection = connection
    }

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}

/// WebSocket server bound to 127.0.0.1 that the browser extension connects to.
/// Handshakes are only accepted from allow-listed `chrome-extension://` origins.
final class BridgeServer {
    static let defaultPort: UInt16 = 47823

    var onConnect: ((BridgeClient) -> Void)?
    var onMessage: ((BridgeClient, Data) -> Void)?
    var onDisconnect: ((BridgeClient) -> Void)?
    /// Called with a human-readable error while the listener is down, nil once it is up.
    var onListenerError: ((String?) -> Void)?

    private let port: UInt16
    private let isOriginAllowed: (String?) -> Bool
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: BridgeClient] = [:]

    init(port: UInt16 = BridgeServer.defaultPort, isOriginAllowed: @escaping (String?) -> Bool) {
        self.port = port
        self.isOriginAllowed = isOriginAllowed
    }

    func start() {
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.setClientRequestHandler(.main) { [isOriginAllowed] _, headers in
            let origin = headers.first { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }?.value
            let allowed = isOriginAllowed(origin)
            if !allowed { NSLog("TouchTabs: rejected WebSocket handshake from origin \(origin ?? "<none>")") }
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject, subprotocol: nil)
        }

        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)

        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] state in self?.listenerStateChanged(state) }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            onListenerError?(error.localizedDescription)
            retryLater()
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            onListenerError?(nil)
        case .failed(let error):
            NSLog("TouchTabs: listener failed: \(error)")
            onListenerError?("Port \(port) unavailable: \(error.localizedDescription)")
            listener?.cancel()
            listener = nil
            retryLater()
        default:
            break
        }
    }

    private func retryLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.listener == nil else { return }
            self.start()
        }
    }

    private func accept(_ connection: NWConnection) {
        let client = BridgeClient(connection: connection)
        clients[ObjectIdentifier(client)] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .ready:
                self.onConnect?(client)
                self.receive(from: client)
            case .failed, .cancelled:
                self.drop(client)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func receive(from client: BridgeClient) {
        client.connection.receiveMessage { [weak self, weak client] data, context, _, error in
            guard let self, let client else { return }
            if error != nil {
                self.drop(client)
                return
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if metadata?.opcode == .close {
                self.drop(client)
                return
            }
            if metadata?.opcode == .text, let data, !data.isEmpty {
                self.onMessage?(client, data)
            }
            self.receive(from: client)
        }
    }

    private func drop(_ client: BridgeClient) {
        guard clients.removeValue(forKey: ObjectIdentifier(client)) != nil else { return }
        client.connection.cancel()
        onDisconnect?(client)
    }
}
