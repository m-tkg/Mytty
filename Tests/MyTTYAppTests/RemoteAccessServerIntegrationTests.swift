import CryptoKit
import Foundation
import MyTTYRemoteKit
import Network
import Testing

@testable import MyTTYApp

/// Drives the real `RemoteAccessServer` over an actual loopback TCP
/// connection using the same wire protocol as the iOS client, to catch
/// integration bugs (framing, encryption, message ordering) that the
/// pure-logic unit tests can't see.
@MainActor
@Suite("Remote access server integration")
struct RemoteAccessServerIntegrationTests {
    @Test("delivers pane content after watchPane, following the full pair + hello flow")
    func deliversPaneContentAfterWatch() async throws {
        let delegate = StubRemoteAccessDelegate()
        delegate.paneText["pane-1"] = "hello from mac"

        let server = RemoteAccessServer(
            deviceStore: RemotePairedDeviceStore(fileURL: temporaryStoreURL()),
            deviceDisplayName: testServiceName(),
            onError: { error in Issue.record("server error: \(error)") }
        )
        server.delegate = delegate
        log("starting server")
        try server.start()
        defer { server.stop() }

        let port = try await step("wait for listening port") {
            try await self.waitForListeningPort(server)
        }
        log("got port \(port)")
        let code = server.pairingCoordinator.beginPairing()

        let pairConnection = TestRemoteConnection(port: port)
        try await step("pair connection start") { try await pairConnection.start() }
        log("pair connection ready")
        let pairingKey = RemotePairing.derivePresharedKey(code: code.value)
        let approval = try await step("pair exchange") {
            try await pairConnection.exchange(
                .pairRequest(deviceName: "Integration iPhone", code: code.value),
                key: pairingKey
            )
        }
        log("got pairing response \(approval)")
        pairConnection.cancel()
        guard case let .pairApproved(deviceID, secretBase64) = approval else {
            Issue.record("expected pairApproved, got \(approval)")
            return
        }

        let session = TestRemoteConnection(port: port)
        try await step("session connection start") { try await session.start() }
        log("session connection ready")
        defer { session.cancel() }
        let sessionKey = SymmetricKey(
            data: Data(base64Encoded: secretBase64) ?? Data()
        )

        let helloResponse = try await step("hello exchange") {
            try await session.exchange(
                .hello(
                    deviceID: deviceID,
                    protocolVersion: RemoteMessageCodec.protocolVersion
                ),
                key: sessionKey
            )
        }
        log("got hello response \(helloResponse)")
        guard case .snapshot = helloResponse else {
            Issue.record("expected snapshot after hello, got \(helloResponse)")
            return
        }

        let watchResponse = try await step("watchPane exchange") {
            try await session.exchange(
                .watchPane(paneID: "pane-1"),
                key: sessionKey
            )
        }
        log("got watch response \(watchResponse)")
        guard case let .paneContent(
            paneID,
            text,
            cursorRow,
            cursorColumn,
            _,
            _
        ) = watchResponse
        else {
            Issue.record("expected paneContent after watchPane, got \(watchResponse)")
            return
        }
        #expect(paneID == "pane-1")
        #expect(text == "hello from mac")
        #expect(cursorRow == 1)
        #expect(cursorColumn == 2)
    }

    @Test("reports the connected device count as sessions authenticate and disconnect")
    func connectedDeviceCountTracksSessionLifecycle() async throws {
        let delegate = StubRemoteAccessDelegate()
        let server = RemoteAccessServer(
            deviceStore: RemotePairedDeviceStore(fileURL: temporaryStoreURL()),
            deviceDisplayName: testServiceName(),
            onError: { error in Issue.record("server error: \(error)") }
        )
        server.delegate = delegate
        var observedCounts: [Int] = []
        server.onConnectedDeviceCountChanged = { observedCounts.append($0) }
        try server.start()
        defer { server.stop() }

        #expect(server.connectedDeviceCount == 0)

        let port = try await step("wait for listening port") {
            try await self.waitForListeningPort(server)
        }
        let code = server.pairingCoordinator.beginPairing()

        let pairConnection = TestRemoteConnection(port: port)
        try await step("pair connection start") { try await pairConnection.start() }
        let pairingKey = RemotePairing.derivePresharedKey(code: code.value)
        let approval = try await step("pair exchange") {
            try await pairConnection.exchange(
                .pairRequest(deviceName: "Integration iPhone", code: code.value),
                key: pairingKey
            )
        }
        pairConnection.cancel()
        guard case let .pairApproved(deviceID, secretBase64) = approval else {
            Issue.record("expected pairApproved, got \(approval)")
            return
        }
        #expect(server.connectedDeviceCount == 0)

        let session = TestRemoteConnection(port: port)
        try await step("session connection start") { try await session.start() }
        let sessionKey = SymmetricKey(
            data: Data(base64Encoded: secretBase64) ?? Data()
        )
        _ = try await step("hello exchange") {
            try await session.exchange(
                .hello(
                    deviceID: deviceID,
                    protocolVersion: RemoteMessageCodec.protocolVersion
                ),
                key: sessionKey
            )
        }
        #expect(server.connectedDeviceCount == 1)
        #expect(observedCounts == [1])

        session.cancel()
        for _ in 0..<100 where server.connectedDeviceCount != 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(observedCounts == [1, 0])
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[debug] \(message)\n".utf8))
    }

    private struct StepTimeoutError: Error, CustomStringConvertible {
        let name: String
        var description: String { "timed out waiting for: \(name)" }
    }

    private func step<T: Sendable>(
        _ name: String,
        seconds: Double = 5,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        log("start: \(name)")
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw StepTimeoutError(name: name)
            }
            let result = try await group.next()!
            group.cancelAll()
            log("done: \(name)")
            return result
        }
    }

    private func waitForListeningPort(
        _ server: RemoteAccessServer
    ) async throws -> UInt16 {
        for _ in 0..<50 {
            if let port = server.listeningPort { return port }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("server never reported a listening port")
        throw RemoteAccessServerError.listenerFailed("timed out")
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("remote-devices.json", isDirectory: false)
    }

    private func testServiceName() -> String {
        "Mytty Test \(UUID().uuidString)"
    }
}

@MainActor
private final class StubRemoteAccessDelegate: RemoteAccessServerDelegate {
    var paneText: [String: String] = [:]

    func remoteAccessServerSnapshot(
        _ server: RemoteAccessServer
    ) -> RemoteSessionSnapshot {
        RemoteSessionSnapshot(windows: [])
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        contentForPaneID paneID: String
    ) -> RemotePaneContent? {
        paneText[paneID].map {
            RemotePaneContent(text: $0, cursorRow: 1, cursorColumn: 2)
        }
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        sendText text: String,
        pressEnter: Bool,
        toPaneID paneID: String
    ) {}

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        pressKey key: String,
        modifiers: [String],
        toPaneID paneID: String
    ) {}

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        scrollBy deltaY: Double,
        inPaneID paneID: String
    ) {}

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        createTabInWindowID windowID: String
    ) {}
}

/// Minimal NWConnection-based client mirroring the iOS app's
/// `RemoteConnectionTransport` closely enough to drive the real protocol
/// over loopback from a test.
private final class TestRemoteConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "test.remote-client")
    private var frameReader = RemoteFrameReader()
    private var pendingFrame: CheckedContinuation<Data, Error>?

    init(port: UInt16) {
        connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
    }

    private final class ResumeOnceBox<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false
        var continuation: CheckedContinuation<T, Error>?

        func resume(returning value: T) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume, let continuation else { return }
            didResume = true
            continuation.resume(returning: value)
        }

        func resume(throwing error: Error) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume, let continuation else { return }
            didResume = true
            continuation.resume(throwing: error)
        }
    }

    func start() async throws {
        let box = ResumeOnceBox<Void>()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.continuation = continuation
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume(returning: ())
                case let .failed(error):
                    box.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        receiveLoop()
    }

    func cancel() {
        connection.cancel()
    }

    /// Encrypts and sends `message`, then waits for and decrypts the next
    /// frame the server sends back.
    func exchange(
        _ message: RemoteMessage,
        key: SymmetricKey
    ) async throws -> RemoteMessage {
        let payload = try RemoteMessageCodec.encode(message)
        let sealed = try RemoteSecureChannel.seal(payload, using: key)
        let frame = RemoteFrameCodec.encode(sealed)

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            self.pendingFrame = continuation
            self.connection.send(
                content: frame,
                completion: .contentProcessed { _ in }
            )
        }
        let opened = try RemoteSecureChannel.open(responseData, using: key)
        return try RemoteMessageCodec.decode(opened)
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
                        self.pendingFrame?.resume(returning: frame)
                        self.pendingFrame = nil
                    }
                }
            }
            if let error {
                self.pendingFrame?.resume(throwing: error)
                self.pendingFrame = nil
            }
            if !isComplete && error == nil {
                self.receiveLoop()
            }
        }
    }
}
