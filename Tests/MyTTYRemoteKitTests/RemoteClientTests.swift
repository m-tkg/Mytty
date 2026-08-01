import Foundation
import Network
import Testing
@testable import MyTTYRemoteKit

@MainActor
@Suite
struct RemoteClientTests {
    @Test
    func staleCloseFromPreviousTransportDoesNotFailReconnect() async {
        var transports: [RemoteConnectionTransporting] = []
        let client = RemoteClient(makeTransport: { endpoint in
            let transport = FakeRemoteConnectionTransport(endpoint: endpoint)
            transports.append(transport)
            return transport
        })
        let mac = PairedMac(
            deviceID: "mac-1",
            deviceSecretBase64: Data(repeating: 1, count: 32).base64EncodedString(),
            macName: "Mac",
            displayName: "Mac"
        )

        client.connect(mac: mac)
        let first = transports[0]
        client.reconnect()
        #expect(client.state == .connecting)

        first.onClose?(nil)
        await Task.yield()

        #expect(client.state == .connecting)
        #expect(transports.count == 2)

        transports[1].onClose?(nil)
        await Task.yield()

        #expect(client.state == .disconnected)
    }
}

private final class FakeRemoteConnectionTransport:
    RemoteConnectionTransporting,
    @unchecked Sendable
{
    var onReady: (@Sendable () -> Void)?
    var onFrame: (@Sendable (Data) -> Void)?
    var onClose: (@Sendable (Error?) -> Void)?

    let endpoint: NWEndpoint

    init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
    }

    func start() {}
    func send(_ data: Data) {}
    func cancel() {}
}
