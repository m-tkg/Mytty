import Foundation
import Testing

@testable import MyTTYApp

@MainActor
@Suite("Remote access server startup")
struct RemoteAccessServerStartupTests {
    @Test("starting the server returns without hanging")
    func startReturns() throws {
        FileHandle.standardError.write(Data("[minimal] before start\n".utf8))
        let server = RemoteAccessServer(
            deviceStore: RemotePairedDeviceStore(fileURL: tempURL()),
            deviceDisplayName: testServiceName(),
            onError: { _ in }
        )
        try server.start()
        FileHandle.standardError.write(Data("[minimal] after start, port=\(String(describing: server.listeningPort))\n".utf8))
        server.stop()
        FileHandle.standardError.write(Data("[minimal] after stop\n".utf8))
    }

    @Test("listeningPort never reports the unbound placeholder port zero")
    func listeningPortIsNeverZero() throws {
        let server = RemoteAccessServer(
            deviceStore: RemotePairedDeviceStore(fileURL: tempURL()),
            deviceDisplayName: testServiceName(),
            onError: { _ in }
        )
        // Immediately after start() the listener has not necessarily
        // reached .ready yet, so listeningPort must read nil rather than
        // the NWListener "any port" placeholder (0) — a value 0 would
        // make a caller construct an unconnectable endpoint.
        try server.start()
        #expect(server.listeningPort != 0)
        server.stop()
    }

    @Test("isActive is true immediately after start, even before the listener is ready")
    func isActiveTracksStartStopRegardlessOfReadiness() throws {
        let server = RemoteAccessServer(
            deviceStore: RemotePairedDeviceStore(fileURL: tempURL()),
            deviceDisplayName: testServiceName(),
            onError: { _ in }
        )
        #expect(!server.isActive)
        try server.start()
        #expect(server.isActive)
        server.stop()
        #expect(!server.isActive)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("remote-devices.json", isDirectory: false)
    }

    private func testServiceName() -> String {
        "Mytty Test \(UUID().uuidString)"
    }
}
