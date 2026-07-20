import Foundation
import Network

/// Raw Network.framework plumbing for the remote-control listener: accepts
/// connections, advertises the service over Bonjour, and relays bytes in
/// and out. It knows nothing about the remote-control protocol; that lives
/// in `RemoteAccessServer`, which drives this class through callbacks the
/// same way `AgentEventServer` drives `UnixSocketTransport`.
final class RemoteAccessTransport: @unchecked Sendable {
    typealias ConnectionID = ObjectIdentifier

    static let serviceType = "_mytty._tcp"
    private static let maximumFrameChunk = 64 * 1024

    var onAccept: (@Sendable (ConnectionID) -> Void)?
    var onData: (@Sendable (ConnectionID, Data) -> Void)?
    var onClose: (@Sendable (ConnectionID) -> Void)?
    var onListenerError: (@Sendable (Error) -> Void)?

    private let queue = DispatchQueue(label: "dev.mytty.remote-access")
    private var listener: NWListener?
    private var connections: [ConnectionID: NWConnection] = [:]

    /// `NWListener.port` reports port `0` (`.any`) until the listener
    /// actually reaches `.ready`, so callers must not treat it as a real,
    /// connectable port before then.
    var listeningPort: UInt16? {
        guard let port = listener?.port?.rawValue, port != 0 else {
            return nil
        }
        return port
    }

    /// Starts listening, preferring `preferredPort` so manual/VPN clients
    /// can reach the Mac at a predictable address (Bonjour carries the
    /// real port either way, but Tailscale-style setups type it in by
    /// hand). When the preferred port cannot be bound — including the
    /// asynchronous address-in-use failure — the listener falls back to
    /// an ephemeral port instead of staying dead.
    func start(serviceName: String, preferredPort: UInt16? = nil) throws {
        stop()
        if let preferredPort,
           let listener = try? makeListener(
               serviceName: serviceName,
               port: preferredPort
           ) {
            listener.stateUpdateHandler = { [weak self] state in
                guard case let .failed(error) = state, let self else {
                    return
                }
                self.queue.async {
                    listener.cancel()
                    guard let fallback = try? self.makeListener(
                        serviceName: serviceName,
                        port: nil
                    ) else {
                        self.onListenerError?(error)
                        return
                    }
                    fallback.stateUpdateHandler = { [weak self] state in
                        if case let .failed(error) = state {
                            self?.onListenerError?(error)
                        }
                    }
                    fallback.start(queue: self.queue)
                    self.listener = fallback
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            return
        }

        let listener = try makeListener(serviceName: serviceName, port: nil)
        listener.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                self?.onListenerError?(error)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func makeListener(
        serviceName: String,
        port: UInt16?
    ) throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        // Deliberately no allowLocalEndpointReuse: SO_REUSEPORT would let
        // a second Mytty (e.g. a dev build) silently share the preferred
        // port instead of falling back to an ephemeral one.
        let listener: NWListener
        if let port, let nwPort = NWEndpoint.Port(rawValue: port) {
            listener = try NWListener(using: parameters, on: nwPort)
        } else {
            listener = try NWListener(using: parameters)
        }
        listener.service = NWListener.Service(
            name: serviceName,
            type: Self.serviceType
        )
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async {
                self.accept(connection)
            }
        }
        return listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    func send(
        _ data: Data,
        to id: ConnectionID,
        completion: (@Sendable () -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let connection = self?.connections[id] else {
                completion?()
                return
            }
            connection.send(
                content: data,
                completion: .contentProcessed { _ in
                    completion?()
                }
            )
        }
    }

    func cancel(_ id: ConnectionID) {
        queue.async { [weak self] in
            self?.connections[id]?.cancel()
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ConnectionID(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.finish(id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        onAccept?(id)
        receiveLoop(id: id, connection: connection)
    }

    private func receiveLoop(id: ConnectionID, connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: Self.maximumFrameChunk
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.onData?(id, data)
            }
            if isComplete || error != nil {
                self.finish(id)
                return
            }
            self.receiveLoop(id: id, connection: connection)
        }
    }

    private func finish(_ id: ConnectionID) {
        queue.async { [weak self] in
            guard let self, self.connections.removeValue(forKey: id) != nil
            else { return }
            self.onClose?(id)
        }
    }
}
