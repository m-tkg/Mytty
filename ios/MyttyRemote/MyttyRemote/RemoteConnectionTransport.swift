import Foundation
import Network
import MyTTYRemoteKit

/// Raw Network.framework plumbing for a single outbound connection to the
/// Mac. Mirrors `RemoteAccessTransport` on the Mac side: this class only
/// moves bytes and frames them, leaving protocol/crypto decisions to
/// `RemoteClient`.
final class RemoteConnectionTransport: @unchecked Sendable {
    var onReady: (@Sendable () -> Void)?
    var onFrame: (@Sendable (Data) -> Void)?
    var onClose: (@Sendable (Error?) -> Void)?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "dev.mytty.remote-client")
    private var frameReader = RemoteFrameReader()

    init(endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: .tcp)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onReady?()
            case let .failed(error):
                self.onClose?(error)
            case .cancelled:
                self.onClose?(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop()
    }

    func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
    }

    private func receiveLoop() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                if let frames = try? self.frameReader.append(data) {
                    for frame in frames {
                        self.onFrame?(frame)
                    }
                } else {
                    self.onClose?(error)
                    return
                }
            }
            if isComplete || error != nil {
                self.onClose?(error)
                return
            }
            self.receiveLoop()
        }
    }
}
