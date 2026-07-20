import CryptoKit
import Foundation
import MyTTYRemoteKit

/// The alert as the phone will read it, before sealing. Sent as JSON
/// inside the ciphertext so the relay only ever handles an opaque blob.
struct PushRelayAlert: Codable, Equatable, Sendable {
    var title: String
    var body: String
    var paneID: String?
}

enum PushRelayError: Error, Equatable {
    case notRegistered
    case invalidRelaySecret
    /// The relay answered with a non-2xx status; `reason` is the `error`
    /// field it reports, which for APNs rejections is Apple's own reason
    /// string (`BadDeviceToken`, `InvalidProviderToken`, …).
    case rejected(status: Int, reason: String?)
}

/// One phone's relay registration plus the pairing key its alerts are
/// sealed with. The relay authorises on `relaySecret` and never sees
/// `pairingKey`; the phone holds both.
struct PushRelayTarget: Equatable {
    let macDeviceID: String
    let pushID: String
    let relaySecret: Data
    let pairingKey: SymmetricKey

    init?(device: RemotePairedDevice) {
        guard let pushID = device.pushRelayID, !pushID.isEmpty,
              let secretBase64 = device.pushRelaySecretBase64,
              let relaySecret = Data(base64Encoded: secretBase64),
              let pairingSecret = Data(base64Encoded: device.secretBase64)
        else { return nil }
        self.macDeviceID = device.id
        self.pushID = pushID
        self.relaySecret = relaySecret
        self.pairingKey = SymmetricKey(data: pairingSecret)
    }
}

/// Signs and posts sealed alerts to the push relay. Kept free of any
/// knowledge of APNs: the provider key, the device token, and the choice
/// of Apple host all live in the Worker.
struct PushRelayRequestBuilder {
    static func makeRequest(
        alert: PushRelayAlert,
        target: PushRelayTarget,
        collapseID: String,
        baseURL: URL,
        timestamp: Date
    ) throws -> URLRequest {
        let sealed = try RemoteSecureChannel.seal(
            try JSONEncoder().encode(alert),
            using: target.pairingKey
        )
        let body = try JSONEncoder().encode(
            RelayPushBody(
                macID: target.macDeviceID,
                ciphertext: sealed.base64EncodedString(),
                collapseID: collapseID,
                title: PushRelay.placeholderTitle,
                placeholder: alert.title
            )
        )
        let seconds = Int(timestamp.timeIntervalSince1970)
        var request = URLRequest(url: PushRelay.pushURL(base: baseURL))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(target.pushID, forHTTPHeaderField: "x-mytty-push-id")
        request.setValue("\(seconds)", forHTTPHeaderField: "x-mytty-timestamp")
        request.setValue(
            signature(secret: target.relaySecret, timestamp: seconds, body: body),
            forHTTPHeaderField: "x-mytty-signature"
        )
        return request
    }

    /// Covers the timestamp as well as the body, so a captured request
    /// cannot be replayed outside the relay's freshness window.
    static func signature(secret: Data, timestamp: Int, body: Data) -> String {
        var signed = Data("\(timestamp).".utf8)
        signed.append(body)
        let mac = HMAC<SHA256>.authenticationCode(
            for: signed,
            using: SymmetricKey(data: secret)
        )
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// The placeholder the relay puts in the visible alert is what a
    /// phone shows when it cannot decrypt, so it carries the Attention
    /// kind ("Approval requested") but never the agent's message.
    private struct RelayPushBody: Encodable {
        let macID: String
        let ciphertext: String
        let collapseID: String
        let title: String
        let placeholder: String
    }

    static func failureReason(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary["error"] as? String
    }
}

actor PushRelayClient {
    /// Injected so tests never touch the network.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport
    private let baseURL: URL
    private let now: @Sendable () -> Date

    init(
        baseURL: URL = PushRelay.defaultURL,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.now = now
    }

    func send(
        _ alert: PushRelayAlert,
        to target: PushRelayTarget,
        collapseID: String
    ) async throws {
        let request = try PushRelayRequestBuilder.makeRequest(
            alert: alert,
            target: target,
            collapseID: collapseID,
            baseURL: baseURL,
            timestamp: now()
        )
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw PushRelayError.rejected(
                status: http.statusCode,
                reason: PushRelayRequestBuilder.failureReason(from: data)
            )
        }
    }
}
