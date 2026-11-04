import Darwin
import Foundation
import Testing

@testable import MyTTYCore

/// A Unix socket server that accepts connections and then does whatever the
/// test asked for, so the client's failure handling can be exercised
/// without a real `AgentEventServer`.
private final class StubSocketServer: @unchecked Sendable {
    enum Behavior: Equatable {
        /// Accept and never answer, so the client's receive timeout fires.
        case hang
        /// Accept, read the request, and reply with a valid response.
        case reply
        /// Like `.reply`, but only after a pause, so a client that already
        /// gave up and closed is written to.
        case slowReply
    }

    let url: URL
    private let directory: URL
    private var listener: Int32 = -1
    private var thread: Thread?
    private let lock = NSLock()
    private var _connectionCount = 0
    private var _stopped = false
    private let loopDone = DispatchSemaphore(value: 0)

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _stopped
    }

    /// How many times a client connected. The retry is only observable
    /// from the outside as a second connection.
    var connectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _connectionCount
    }

    /// `acceptDelay` pauses the accept loop before every `accept`, which is
    /// what a thread starved by a loaded machine looks like. It lets a test
    /// hit the descriptor-reuse window deterministically.
    init(behavior: Behavior, acceptDelay: TimeInterval = 0) throws {
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

        // Deliberately not named `listener`: a local shadowing the property
        // makes the `bind` closure above resolve to it, which older Swift
        // compilers (the CI runner's) reject as a capture before
        // declaration.
        let acceptSocket = self.listener
        let loopDone = self.loopDone
        let thread = Thread { [weak self] in
            defer { loopDone.signal() }
            while true {
                if acceptDelay > 0 { Thread.sleep(forTimeInterval: acceptDelay) }
                // Checked before every accept: once `stop()` has run, the
                // descriptor number may belong to another server, and
                // accepting on it would steal that server's connection.
                guard let self, !self.isStopped else { return }
                let client = Darwin.accept(acceptSocket, nil, nil)
                guard client >= 0 else { return }
                guard !self.isStopped else {
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
        // The client's SO_NOSIGPIPE does not cover this end, and setting it
        // on an accepted socket whose peer already closed fails with EINVAL
        // on Darwin. Replying to a connection the client closed would raise
        // SIGPIPE and kill the whole test process, so ignore the signal;
        // the failed `send` just returns EPIPE.
        signal(SIGPIPE, SIG_IGN)
        switch behavior {
        case .hang:
            // Hold the connection open without answering; the client's
            // SO_RCVTIMEO is what ends the exchange.
            Thread.sleep(forTimeInterval: 2)
        case .reply, .slowReply:
            var buffer = [UInt8](repeating: 0, count: 4096)
            _ = Darwin.recv(client, &buffer, buffer.count, 0)
            if behavior == .slowReply { Thread.sleep(forTimeInterval: 0.2) }
            let response = Data(#"{"ok":true,"inserted":true}"#.utf8)
                + Data([0x0A])
            _ = response.withUnsafeBytes {
                Darwin.send(client, $0.baseAddress, $0.count, 0)
            }
        }
    }

    func stop() {
        lock.lock()
        let alreadyStopped = _stopped
        _stopped = true
        lock.unlock()
        guard !alreadyStopped else { return }

        // Closing the listener while the accept loop may still call
        // `accept` on that number is a race: the number can be handed to
        // the next test's socket, and the stale loop then steals its
        // connections and drops them (the client sees `emptyResponse`).
        // So wake the loop with a throwaway connection, wait until it has
        // exited, and only then release the descriptor.
        wakeAcceptLoop()
        // Bounded so a failed wake-up cannot hang the whole suite. On a
        // timeout the descriptor is leaked on purpose: closing it under a
        // live loop is exactly the reuse hazard this guards against.
        guard loopDone.wait(timeout: .now() + 5) == .success else { return }
        if listener >= 0 {
            Darwin.close(listener)
            listener = -1
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func wakeAcceptLoop() {
        let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return }
        defer { Darwin.close(probe) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(url.path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        _ = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    probe,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
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

    @Test("a stopped stub server never steals a reused descriptor")
    func stoppedServerReleasesItsDescriptor() throws {
        // The first server's accept loop is held back the way a starved
        // thread on a loaded machine is. Stopping it must wait for that
        // loop; otherwise the descriptor number is reused by the second
        // server and the stale loop accepts (and drops) its connection,
        // which the client reports as `emptyResponse`.
        let stale = try StubSocketServer(behavior: .hang, acceptDelay: 0.3)
        stale.stop()

        let server = try StubSocketServer(behavior: .reply, acceptDelay: 0.7)
        defer { server.stop() }

        // Let a stale loop, if there is one, wake up and block in accept.
        Thread.sleep(forTimeInterval: 0.5)

        let response = try AgentEventSocketClient(operationTimeout: 2)
            .send(envelope(), to: server.url)
        #expect(response.ok)
        #expect(server.connectionCount == 1)
        #expect(stale.connectionCount == 0)
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

    @Test("a half-close ENOTCONN does not discard an available response")
    func enotconnOnHalfCloseIsIgnored() throws {
        let server = try StubSocketServer(behavior: .reply)
        defer { server.stop() }

        let response = try AgentEventSocketClient(
            operationTimeout: 2,
            halfClose: { _ in ENOTCONN }
        ).send(envelope(), to: server.url)

        #expect(response.ok)
    }

    @Test("other half-close errors are still reported")
    func otherHalfCloseErrorsThrow() throws {
        let server = try StubSocketServer(behavior: .slowReply)
        defer { server.stop() }

        #expect(throws: AgentEventSocketClientError.socketOperation(EIO)) {
            try AgentEventSocketClient(
                operationTimeout: 2,
                halfClose: { _ in EIO }
            ).send(envelope(), to: server.url)
        }
    }
}
