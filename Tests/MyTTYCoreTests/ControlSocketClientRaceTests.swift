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
        let fixture = try ReplyingServer()
        defer { fixture.stop() }

        #expect(throws: ControlSocketClientError.socketOperation(EIO)) {
            try ControlSocketClient(halfClose: { _ in EIO }).send(
                .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 10),
                to: fixture.socketURL,
                timeoutSeconds: 10
            )
        }
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
        private let listener: Int32

        init() throws {
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
            Thread {
                while true {
                    let client = Darwin.accept(descriptor, nil, nil)
                    guard client >= 0 else { return }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    _ = Darwin.recv(client, &buffer, buffer.count, 0)
                    reply.withUnsafeBytes {
                        _ = Darwin.send(client, $0.baseAddress, $0.count, 0)
                    }
                    Darwin.close(client)
                }
            }.start()
        }

        func stop() {
            Darwin.close(listener)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
