import Foundation
import Testing

@testable import MyTTYApp

@Suite("Remote access transport", .serialized)
struct RemoteAccessTransportTests {
    @Test("binds the preferred port when it is free")
    func bindsPreferredPort() async throws {
        let probe = RemoteAccessTransport()
        try probe.start(serviceName: "mytty-test-probe")
        let freePort = try #require(await listeningPort(of: probe))
        probe.stop()

        // NWListener.cancel() releases the port asynchronously, so give
        // the probe's port a moment to actually free up before expecting
        // the preferred bind to win (CI loses this race more than a dev
        // machine does).
        var boundPort: UInt16?
        for _ in 0..<20 {
            let transport = RemoteAccessTransport()
            try transport.start(
                serviceName: "mytty-test-preferred",
                preferredPort: freePort
            )
            boundPort = await listeningPort(of: transport)
            transport.stop()
            if boundPort == freePort {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(boundPort == freePort)
    }

    @Test("falls back to an ephemeral port when the preferred one is taken")
    func fallsBackWhenPreferredPortTaken() async throws {
        let occupant = RemoteAccessTransport()
        defer { occupant.stop() }
        try occupant.start(serviceName: "mytty-test-occupant")
        let takenPort = try #require(await listeningPort(of: occupant))

        let transport = RemoteAccessTransport()
        defer { transport.stop() }
        try transport.start(
            serviceName: "mytty-test-fallback",
            preferredPort: takenPort
        )
        let port = try #require(await listeningPort(of: transport))
        #expect(port != takenPort)
    }

    private func listeningPort(
        of transport: RemoteAccessTransport
    ) async -> UInt16? {
        for _ in 0..<100 {
            if let port = transport.listeningPort {
                return port
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }
}
