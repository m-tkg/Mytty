import Darwin
import Foundation
import Testing

@testable import MyTTYCore

/// A Unix socket server that accepts connections and then does whatever the
/// test asked for, so the client's failure handling can be exercised
/// without a real `AgentEventServer`.
private final class StubSocketServer: @unchecked Sendable {
    enum Behavior {
        /// Accept and never answer, so the client's receive timeout fires.
        case hang
        /// Accept, read the request, and reply with a valid response.
        case reply
    }

    let url: URL
    private let directory: URL
    private var listener: Int32 = -1
    private var thread: Thread?
    private let lock = NSLock()
    private var _connectionCount = 0

    /// How many times a client connected. The retry is only observable
    /// from the outside as a second connection.
    var connectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _connectionCount
    }

    init(behavior: Behavior) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appendingPathComponent("stub.sock")

        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(listener >= 0)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(url.path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    listener,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        try #require(bound == 0)
        try #require(Darwin.listen(listener, 8) == 0)

        let listener = self.listener
        let thread = Thread { [weak self] in
            while true {
                let client = Darwin.accept(listener, nil, nil)
                guard client >= 0 else { return }
                guard let self else {
                    Darwin.close(client)
                    return
                }
                self.lock.lock()
                self._connectionCount += 1
                self.lock.unlock()

                // Each connection is served on its own thread so the accept
                // loop stays free: a `.hang` connection holding this loop
                // would make the client's retry invisible, since the second
                // connect would never be accepted.
                Thread { Self.serve(client: client, behavior: behavior) }
                    .start()
            }
        }
        thread.start()
        self.thread = thread
    }

    private static func serve(client: Int32, behavior: Behavior) {
        defer { Darwin.close(client) }
        switch behavior {
        case .hang:
            // Hold the connection open without answering; the client's
            // SO_RCVTIMEO is what ends the exchange.
            Thread.sleep(forTimeInterval: 2)
        case .reply:
            var buffer = [UInt8](repeating: 0, count: 4096)
            _ = Darwin.recv(client, &buffer, buffer.count, 0)
            let response = Data(#"{"ok":true,"inserted":true}"#.utf8)
                + Data([0x0A])
            _ = response.withUnsafeBytes {
                Darwin.send(client, $0.baseAddress, $0.count, 0)
            }
        }
    }

    func stop() {
        if listener >= 0 {
            Darwin.close(listener)
            listener = -1
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite("Agent event socket client retry")
struct AgentEventSocketClientRetryTests {
    private func envelope() -> AgentEventEnvelope {
        AgentEventEnvelope(
            capability: "capability",
            event: AgentEvent(
                id: AgentEventID(rawValue: UUID()),
                runID: AgentRunID(rawValue: UUID()),
                surfaceID: TerminalSurfaceID(),
                provider: .codex,
                kind: .started,
                occurredAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    @Test("a socket timeout is retried once on a fresh connection")
    func timeoutIsRetried() throws {
        let server = try StubSocketServer(behavior: .hang)
        defer { server.stop() }

        let client = AgentEventSocketClient(operationTimeout: 0.2)
        #expect(throws: AgentEventSocketClientError.self) {
            _ = try client.send(envelope(), to: server.url)
        }

        // Two connections is the whole point: a server that is merely slow
        // must get a second chance, which is what the CI flake this fixes
        // never got.
        #expect(server.connectionCount == 2)
    }

    @Test("the retry's own timeout still surfaces as EAGAIN")
    func timeoutStillThrows() throws {
        let server = try StubSocketServer(behavior: .hang)
        defer { server.stop() }

        let client = AgentEventSocketClient(operationTimeout: 0.2)
        do {
            _ = try client.send(envelope(), to: server.url)
            Issue.record("expected the send to throw")
        } catch let AgentEventSocketClientError.socketOperation(code) {
            #expect(code == EAGAIN)
        }
    }

    @Test("a server that answers is not retried")
    func successIsNotRetried() throws {
        let server = try StubSocketServer(behavior: .reply)
        defer { server.stop() }

        let client = AgentEventSocketClient(operationTimeout: 2)
        let response = try client.send(envelope(), to: server.url)
        #expect(response.ok)
        #expect(response.inserted == true)
        #expect(server.connectionCount == 1)
    }

    @Test("only transient failures are worth a second attempt")
    func retryableCodes() {
        #expect(AgentEventSocketClient.isRetryable(EAGAIN))
        #expect(AgentEventSocketClient.isRetryable(EWOULDBLOCK))
        #expect(AgentEventSocketClient.isRetryable(EPIPE))
        #expect(AgentEventSocketClient.isRetryable(ECONNRESET))

        // A missing socket or a sandbox denial will fail exactly the same
        // way a second time; retrying only doubles the wait.
        #expect(!AgentEventSocketClient.isRetryable(ENOENT))
        #expect(!AgentEventSocketClient.isRetryable(ECONNREFUSED))
        #expect(!AgentEventSocketClient.isRetryable(EPERM))
    }
}
