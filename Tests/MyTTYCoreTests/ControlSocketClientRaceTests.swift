import Darwin
import Foundation
import Testing

@testable import MyTTYCore

/// The server may answer and close before the client has half-closed its
/// write side. On Darwin `shutdown(SHUT_WR)` then fails with ENOTCONN even
/// though the response is already buffered and readable, which made a fast
/// `wait` (pane already in the target state) fail intermittently.
@Suite("Control socket client against a fast-closing server")
struct ControlSocketClientRaceTests {
    /// Deterministic: the half-close is forced to report ENOTCONN while a
    /// valid response is waiting, which is what the race produces.
    @Test("a half-close ENOTCONN does not discard an available response")
    func enotconnOnHalfCloseIsIgnored() throws {
        let fixture = try ReplyingServer()
        defer { fixture.stop() }

        let result = try ControlSocketClient(halfClose: { _ in ENOTCONN }).send(
            .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 10),
            to: fixture.socketURL,
            timeoutSeconds: 10
        )
        #expect(result == .waitResult(state: "idle", timedOut: false))
    }

    @Test("other half-close errors are still reported")
    func otherHalfCloseErrorsThrow() throws {
        // The client closes right after the injected error; replying late
        // makes the server write into that closed connection.
        let fixture = try ReplyingServer(replyDelay: 0.2)
        defer { fixture.stop() }

        #expect(throws: ControlSocketClientError.socketOperation(EIO)) {
            try ControlSocketClient(halfClose: { _ in EIO }).send(
                .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 10),
                to: fixture.socketURL,
                timeoutSeconds: 10
            )
        }
    }

    @Test("a stopped server never steals a reused descriptor")
    func stoppedServerReleasesItsDescriptor() throws {
        // The first server's accept loop is held back the way a starved
        // thread on a loaded machine is. Stopping it must wait for that
        // loop; otherwise the descriptor number is reused by the second
        // server and the stale loop accepts (and drops) its connection.
        let stale = try ReplyingServer(acceptDelay: 0.3)
        stale.stop()

        let server = try ReplyingServer(acceptDelay: 0.7)
        defer { server.stop() }

        // Let a stale loop, if there is one, wake up and block in accept.
        Thread.sleep(forTimeInterval: 0.5)

        let result = try ControlSocketClient().send(
            .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 10),
            to: server.socketURL,
            timeoutSeconds: 2
        )
        #expect(result == .waitResult(state: "idle", timedOut: false))
        #expect(server.connectionCount == 1)
        #expect(stale.connectionCount == 0)
    }

    /// Supplementary stress check against the real `shutdown`; the two
    /// deterministic tests above are what pin the behavior.
    @Test("reads the response even when the server closes right after replying")
    func survivesServerClosingBeforeHalfClose() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                String(UUID().uuidString.prefix(8)),
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketURL = directory.appendingPathComponent("c.sock")

        let listener = try Self.makeListener(path: socketURL.path)
        defer { Darwin.close(listener) }
        var response = try ControlMessageCodec.encode(
            ControlResponse.waitResult(state: "idle", timedOut: false)
        )
        response.append(0x0A)
        let reply = response
        let iterations = 1_000
        let server = Thread {
            for _ in 0..<iterations {
                let client = Darwin.accept(listener, nil, nil)
                guard client >= 0 else { return }
                Self.suppressSIGPIPE(client)
                var byte: UInt8 = 0
                // Reply as soon as the request's first byte arrives, then
                // close without waiting for the client's half-close.
                _ = Darwin.recv(client, &byte, 1, 0)
                reply.withUnsafeBytes {
                    _ = Darwin.send(client, $0.baseAddress, $0.count, 0)
                }
                Darwin.close(client)
            }
        }
        server.start()

        var failures: [String] = []
        for _ in 0..<iterations {
            do {
                let result = try ControlSocketClient().send(
                    .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 10),
                    to: socketURL,
                    timeoutSeconds: 10
                )
                #expect(result == .waitResult(state: "idle", timedOut: false))
            } catch {
                failures.append("\(error)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failures, e.g. \(failures.first ?? "")")
    }

    /// The client's SO_NOSIGPIPE does not cover the server's end, and
    /// setting it on an accepted socket whose peer already closed fails
    /// with EINVAL on Darwin. Replying to a connection the client closed
    /// would raise SIGPIPE and kill the whole test process, so ignore the
    /// signal for the process; the failed `send` just returns EPIPE.
    fileprivate static func suppressSIGPIPE(_ descriptor: Int32) {
        signal(SIGPIPE, SIG_IGN)
    }

    private static func makeListener(path: String) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        try #require(bound == 0)
        try #require(Darwin.listen(descriptor, 64) == 0)
        return descriptor
    }

    /// A server that answers one request per connection with an idle
    /// `waitResult` and keeps serving until stopped.
    private final class ReplyingServer: @unchecked Sendable {
        let socketURL: URL
        private let directory: URL
        private var listener: Int32
        private let lock = NSLock()
        private var _stopped = false
        private var _connectionCount = 0
        private let loopDone = DispatchSemaphore(value: 0)

        private var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _stopped
        }

        /// How many connections the accept loop took.
        var connectionCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _connectionCount
        }

        /// `acceptDelay` pauses the accept loop before every `accept`, which
        /// is what a thread starved by a loaded machine looks like. It lets
        /// a test hit the descriptor-reuse window deterministically.
        init(replyDelay: TimeInterval = 0, acceptDelay: TimeInterval = 0) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    String(UUID().uuidString.prefix(8)),
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            socketURL = directory.appendingPathComponent("c.sock")
            let descriptor = try ControlSocketClientRaceTests.makeListener(
                path: socketURL.path
            )
            listener = descriptor
            var response = try ControlMessageCodec.encode(
                ControlResponse.waitResult(state: "idle", timedOut: false)
            )
            response.append(0x0A)
            let reply = response
            let loopDone = self.loopDone
            Thread { [weak self] in
                defer { loopDone.signal() }
                while true {
                    if acceptDelay > 0 { Thread.sleep(forTimeInterval: acceptDelay) }
                    // Checked before every accept: once `stop()` has run, the
                    // descriptor number may belong to another server, and
                    // accepting on it would steal that server's connection.
                    guard let self, !self.isStopped else { return }
                    let client = Darwin.accept(descriptor, nil, nil)
                    guard client >= 0 else { return }
                    guard !self.isStopped else {
                        Darwin.close(client)
                        return
                    }
                    self.lock.lock()
                    self._connectionCount += 1
                    self.lock.unlock()
                    ControlSocketClientRaceTests.suppressSIGPIPE(client)
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    _ = Darwin.recv(client, &buffer, buffer.count, 0)
                    if replyDelay > 0 { Thread.sleep(forTimeInterval: replyDelay) }
                    reply.withUnsafeBytes {
                        _ = Darwin.send(client, $0.baseAddress, $0.count, 0)
                    }
                    Darwin.close(client)
                }
            }.start()
        }

        func stop() {
            lock.lock()
            let alreadyStopped = _stopped
            _stopped = true
            lock.unlock()
            guard !alreadyStopped else { return }

            // Closing the listener while the accept loop may still call
            // `accept` on that number lets the number be handed to the next
            // test's socket, and the stale loop then steals its connections.
            // So wake the loop with a throwaway connection, wait until it
            // has exited, and only then release the descriptor.
            wakeAcceptLoop()
            // Bounded so a failed wake-up cannot hang the suite. On a
            // timeout the descriptor is leaked on purpose: closing it under
            // a live loop is exactly the reuse hazard this guards against.
            guard loopDone.wait(timeout: .now() + 5) == .success else { return }
            Darwin.close(listener)
            listener = -1
            try? FileManager.default.removeItem(at: directory)
        }

        private func wakeAcceptLoop() {
            let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard probe >= 0 else { return }
            defer { Darwin.close(probe) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bytes = Array(socketURL.path.utf8CString)
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                bytes.withUnsafeBytes { destination.copyBytes(from: $0) }
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
}
