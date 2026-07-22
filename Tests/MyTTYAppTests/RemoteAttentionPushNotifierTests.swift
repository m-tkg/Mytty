import CryptoKit
import Foundation
import MyTTYCore
import MyTTYRemoteKit
import Testing

@testable import MyTTYApp

@Suite("Push relay target")
struct PushRelayTargetTests {
    static let pairingSecret = Data(repeating: 3, count: 32)
        .base64EncodedString()
    static let relaySecret = Data(repeating: 9, count: 32)
        .base64EncodedString()

    static func makeDevice(
        pushRelayID: String? = nil,
        relaySecretBase64: String? = nil
    ) -> RemotePairedDevice {
        RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: pairingSecret,
            pairedAt: Date(timeIntervalSince1970: 1_000),
            pushRelayID: pushRelayID,
            pushRelaySecretBase64: relaySecretBase64
        )
    }

    @Test("resolves a registered device into a push target")
    func resolvesRegisteredDevice() throws {
        let target = try #require(
            PushRelayTarget(
                device: Self.makeDevice(
                    pushRelayID: "relay-1",
                    relaySecretBase64: Self.relaySecret
                )
            )
        )
        #expect(target.pushID == "relay-1")
        #expect(target.macDeviceID == "device-1")
        #expect(target.relaySecret == Data(base64Encoded: Self.relaySecret))
    }

    @Test("skips devices with no or partial registration")
    func skipsUnregisteredDevices() {
        #expect(PushRelayTarget(device: Self.makeDevice()) == nil)
        #expect(
            PushRelayTarget(
                device: Self.makeDevice(pushRelayID: "relay-1")
            ) == nil
        )
        #expect(
            PushRelayTarget(
                device: Self.makeDevice(
                    pushRelayID: "",
                    relaySecretBase64: Self.relaySecret
                )
            ) == nil
        )
        #expect(
            PushRelayTarget(
                device: Self.makeDevice(
                    pushRelayID: "relay-1",
                    relaySecretBase64: "not base64!"
                )
            ) == nil
        )
    }
}

@Suite("Push registration validation")
struct RemotePushRegistrationValidationTests {
    static let secret = Data(repeating: 1, count: 32).base64EncodedString()

    @Test("accepts what the relay issues")
    func acceptsRelayIssuedValues() {
        #expect(
            RemotePushRegistrationValidation.isValid(
                pushID: UUID().uuidString,
                relaySecretBase64: Self.secret
            )
        )
    }

    /// A paired device is trusted, but not trusted to put arbitrary bytes
    /// into an HTTP header or to shrink the signing key.
    @Test("rejects identifiers and secrets the relay would never issue")
    func rejectsMalformedValues() {
        #expect(
            !RemotePushRegistrationValidation.isValid(
                pushID: "not-a-uuid",
                relaySecretBase64: Self.secret
            )
        )
        #expect(
            !RemotePushRegistrationValidation.isValid(
                pushID: "relay\r\nx-injected: 1",
                relaySecretBase64: Self.secret
            )
        )
        #expect(
            !RemotePushRegistrationValidation.isValid(
                pushID: UUID().uuidString,
                relaySecretBase64: Data(repeating: 1, count: 8)
                    .base64EncodedString()
            )
        )
        #expect(
            !RemotePushRegistrationValidation.isValid(
                pushID: UUID().uuidString,
                relaySecretBase64: "not base64!"
            )
        )
    }
}

@Suite("Push relay client")
struct PushRelayClientTests {
    private static func makeTarget() -> PushRelayTarget {
        PushRelayTarget(
            device: PushRelayTargetTests.makeDevice(
                pushRelayID: "relay-1",
                relaySecretBase64: PushRelayTargetTests.relaySecret
            )
        )!
    }

    @Test("seals the alert so the relay only carries ciphertext")
    func sealsAlertText() throws {
        let target = Self.makeTarget()
        let alert = PushRelayAlert(
            title: "Approval requested",
            body: "codex wants to run rm -rf /tmp/build",
            paneID: "pane-1"
        )

        let request = try PushRelayRequestBuilder.makeRequest(
            alert: alert,
            target: target,
            collapseID: "pane-1",
            baseURL: URL(string: "https://relay.example")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let body = try #require(request.httpBody)
        let text = try #require(String(data: body, encoding: .utf8))
        // The agent's message is the whole reason for encrypting, so it
        // must not appear anywhere in what leaves the Mac.
        #expect(!text.contains("rm -rf"))
        #expect(!text.contains("codex"))
        // The placeholder a phone without the extension shows names the
        // kind of Attention but nothing the agent said.
        #expect(text.contains("Approval requested"))

        let decoded = try JSONSerialization.jsonObject(with: body)
        let payload = try #require(decoded as? [String: Any])
        #expect(payload["macID"] as? String == "device-1")
        #expect(payload["collapseID"] as? String == "pane-1")

        let ciphertext = try #require(payload["ciphertext"] as? String)
        let sealed = try #require(Data(base64Encoded: ciphertext))
        let opened = try RemoteSecureChannel.open(
            sealed,
            using: target.pairingKey
        )
        #expect(try JSONDecoder().decode(PushRelayAlert.self, from: opened)
            == alert)
    }

    @Test("signs the timestamp together with the body")
    func signsRequest() throws {
        let target = Self.makeTarget()
        let request = try PushRelayRequestBuilder.makeRequest(
            alert: PushRelayAlert(title: "t", body: "b", paneID: nil),
            target: target,
            collapseID: "c",
            baseURL: URL(string: "https://relay.example")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(
            request.url?.absoluteString == "https://relay.example/v1/push"
        )
        #expect(
            request.value(forHTTPHeaderField: "x-mytty-push-id") == "relay-1"
        )
        #expect(
            request.value(forHTTPHeaderField: "x-mytty-timestamp")
                == "1700000000"
        )
        let expected = PushRelayRequestBuilder.signature(
            secret: target.relaySecret,
            timestamp: 1_700_000_000,
            body: try #require(request.httpBody)
        )
        #expect(
            request.value(forHTTPHeaderField: "x-mytty-signature") == expected
        )
    }

    /// Each seal uses a fresh nonce, so two pushes of the same alert do
    /// not produce byte-identical ciphertext a network observer could
    /// correlate.
    @Test("does not repeat ciphertext across sends")
    func usesFreshNonce() throws {
        let target = Self.makeTarget()
        let alert = PushRelayAlert(title: "t", body: "b", paneID: nil)
        func body() throws -> Data {
            let request = try PushRelayRequestBuilder.makeRequest(
                alert: alert,
                target: target,
                collapseID: "c",
                baseURL: URL(string: "https://relay.example")!,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
            return try #require(request.httpBody)
        }
        #expect(try body() != (try body()))
    }

    @Test("surfaces the reason the relay reports for a rejection")
    func surfacesRejectionReason() async throws {
        let client = PushRelayClient(
            baseURL: URL(string: "https://relay.example")!,
            transport: { request in
                (
                    Data(#"{"error":"BadDeviceToken","status":400}"#.utf8),
                    HTTPURLResponse(
                        url: try #require(request.url),
                        statusCode: 502,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await #expect(
            throws: PushRelayError.rejected(
                status: 502,
                reason: "BadDeviceToken"
            )
        ) {
            try await client.send(
                PushRelayAlert(title: "t", body: "b", paneID: nil),
                to: Self.makeTarget(),
                collapseID: "c"
            )
        }
    }

    @Test("treats a 2xx from the relay as delivered")
    func acceptsSuccess() async throws {
        let client = PushRelayClient(
            baseURL: URL(string: "https://relay.example")!,
            transport: { request in
                (
                    Data(#"{"ok":true}"#.utf8),
                    HTTPURLResponse(
                        url: try #require(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )
        try await client.send(
            PushRelayAlert(title: "t", body: "b", paneID: nil),
            to: Self.makeTarget(),
            collapseID: "c"
        )
    }
}

@MainActor
@Suite("Remote attention push notifier body")
struct RemoteAttentionPushNotifierTests {
    private static let surfaceID = TerminalSurfaceID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000301"
    )!)
    private static let pairingSecret = Data(repeating: 5, count: 32)
        .base64EncodedString()
    private static let relaySecret = Data(repeating: 6, count: 32)
        .base64EncodedString()

    private static func makeStore() throws -> RemotePairedDeviceStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = RemotePairedDeviceStore(fileURL: url)
        try store.add(
            RemotePairedDevice(
                id: "device-1",
                name: "iPhone",
                secretBase64: pairingSecret,
                pairedAt: Date(timeIntervalSince1970: 1_000),
                pushRelayID: "relay-1",
                pushRelaySecretBase64: relaySecret
            )
        )
        return store
    }

    private static func makeItem(
        kind: AgentEventKind,
        toolName: String?
    ) -> AttentionItem {
        let runID = AgentRunID(rawValue: UUID())
        let started = AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: .started,
            occurredAt: Date(timeIntervalSince1970: 0)
        )
        let requestEvent = AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: kind,
            occurredAt: Date(timeIntervalSince1970: 1),
            toolName: toolName
        )
        let items = AttentionReducer.reduce(
            events: [started, requestEvent],
            acknowledgements: [],
            now: Date(timeIntervalSince1970: 2)
        )
        return items[0]
    }

    private static func decodeAlert(
        from request: URLRequest
    ) throws -> PushRelayAlert {
        let body = try #require(request.httpBody)
        let object = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let ciphertextBase64 = try #require(object["ciphertext"] as? String)
        let sealed = try #require(Data(base64Encoded: ciphertextBase64))
        let pairingKey = SymmetricKey(
            data: try #require(Data(base64Encoded: pairingSecret))
        )
        let opened = try RemoteSecureChannel.open(sealed, using: pairingKey)
        return try JSONDecoder().decode(PushRelayAlert.self, from: opened)
    }

    private static func makeNotifier(
        localizer: MyTTYLocalizer,
        hostName: @escaping () -> String?,
        capture: RequestCapture
    ) throws -> RemoteAttentionPushNotifier {
        RemoteAttentionPushNotifier(
            deviceStore: try makeStore(),
            client: PushRelayClient(transport: { request in
                await capture.record(request)
                return (
                    Data(#"{"ok":true}"#.utf8),
                    HTTPURLResponse(
                        url: try #require(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }),
            localizer: localizer,
            isEnabled: { true },
            hostName: hostName,
            onError: { _ in }
        )
    }

    @Test("prefixes the body with a host and tab context line when both are known")
    func bodyIncludesHostAndTabContext() async throws {
        let capture = RequestCapture()
        let notifier = try Self.makeNotifier(
            localizer: MyTTYLocalizer(language: .english),
            hostName: { "MacBook Pro" },
            capture: capture
        )

        notifier.notify(
            Self.makeItem(kind: .approvalRequested, toolName: "Bash"),
            tabTitle: "Deploy"
        )

        let alert = try Self.decodeAlert(from: await capture.waitForRequest())
        #expect(alert.body == "MacBook Pro · Deploy\nBash requires approval")
    }

    @Test("shows only the host when no tab title is available")
    func bodyIsHostOnlyWithoutTabTitle() async throws {
        let capture = RequestCapture()
        let notifier = try Self.makeNotifier(
            localizer: MyTTYLocalizer(language: .english),
            hostName: { "MacBook Pro" },
            capture: capture
        )

        notifier.notify(
            Self.makeItem(kind: .approvalRequested, toolName: "Bash"),
            tabTitle: nil
        )

        let alert = try Self.decodeAlert(from: await capture.waitForRequest())
        #expect(alert.body == "MacBook Pro\nBash requires approval")
    }

    @Test("drops the context line entirely when neither host nor tab is known")
    func bodyHasNoContextLineWhenBothAreMissing() async throws {
        let capture = RequestCapture()
        let notifier = try Self.makeNotifier(
            localizer: MyTTYLocalizer(language: .english),
            hostName: { nil },
            capture: capture
        )

        notifier.notify(
            Self.makeItem(kind: .approvalRequested, toolName: "Bash"),
            tabTitle: nil
        )

        let alert = try Self.decodeAlert(from: await capture.waitForRequest())
        #expect(alert.body == "Bash requires approval")
    }

    @Test("localizes the message body in Japanese")
    func bodyIsLocalizedInJapanese() async throws {
        let capture = RequestCapture()
        let notifier = try Self.makeNotifier(
            localizer: MyTTYLocalizer(language: .japanese),
            hostName: { nil },
            capture: capture
        )

        notifier.notify(
            Self.makeItem(kind: .approvalRequested, toolName: "Bash"),
            tabTitle: "デプロイ"
        )

        let alert = try Self.decodeAlert(from: await capture.waitForRequest())
        #expect(alert.body == "デプロイ\nBash の承認が必要です")
    }
}

/// Captures the single request a `PushRelayClient.send` fires, letting an
/// `async` test await it instead of racing the fire-and-forget `Task`
/// inside `RemoteAttentionPushNotifier.notify`.
private actor RequestCapture {
    private var continuation: CheckedContinuation<URLRequest, Never>?
    private var stored: URLRequest?

    func record(_ request: URLRequest) {
        if let continuation {
            continuation.resume(returning: request)
            self.continuation = nil
        } else {
            stored = request
        }
    }

    func waitForRequest() async -> URLRequest {
        if let stored {
            return stored
        }
        return await withCheckedContinuation { continuation = $0 }
    }
}
