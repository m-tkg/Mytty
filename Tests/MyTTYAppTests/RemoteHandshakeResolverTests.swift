import CryptoKit
import Foundation
import MyTTYRemoteKit
import Testing

@testable import MyTTYApp

@Suite("Remote handshake resolver")
struct RemoteHandshakeResolverTests {
    @Test("resolves a pairing request encrypted with the code's derived key")
    func resolvesPairRequest() throws {
        let key = RemotePairing.derivePresharedKey(code: "123456")
        let payload = try RemoteMessageCodec.encode(
            .pairRequest(deviceName: "iPhone", code: "123456")
        )
        let sealed = try RemoteSecureChannel.seal(payload, using: key)

        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: key,
            pairedDevices: []
        )

        guard case let .resolved(message, _) = resolution else {
            Issue.record("expected a resolved handshake, got \(resolution)")
            return
        }
        #expect(message == .pairRequest(deviceName: "iPhone", code: "123456"))
    }

    @Test("resolves hello for a known device using its stored secret")
    func resolvesHelloForKnownDevice() throws {
        let secret = SymmetricKey(size: .bits256)
        let device = RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: secret.withUnsafeBytes { Data($0) }.base64EncodedString(),
            pairedAt: Date()
        )
        let payload = try RemoteMessageCodec.encode(
            .hello(deviceID: "device-1", protocolVersion: 1)
        )
        let sealed = try RemoteSecureChannel.seal(payload, using: secret)

        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: nil,
            pairedDevices: [device]
        )

        guard case let .resolved(message, _) = resolution else {
            Issue.record("expected a resolved handshake, got \(resolution)")
            return
        }
        #expect(
            message == .hello(deviceID: "device-1", protocolVersion: 1)
        )
    }

    @Test("does not authenticate as another device's identity")
    func rejectsMismatchedDeviceIdentity() throws {
        let secretA = SymmetricKey(size: .bits256)
        let secretB = SymmetricKey(size: .bits256)
        let deviceA = RemotePairedDevice(
            id: "device-a",
            name: "iPhone",
            secretBase64: secretA.withUnsafeBytes { Data($0) }.base64EncodedString(),
            pairedAt: Date()
        )
        let deviceB = RemotePairedDevice(
            id: "device-b",
            name: "iPad",
            secretBase64: secretB.withUnsafeBytes { Data($0) }.base64EncodedString(),
            pairedAt: Date()
        )
        // Encrypted with device B's secret but claims to be device A.
        let payload = try RemoteMessageCodec.encode(
            .hello(deviceID: "device-a", protocolVersion: 1)
        )
        let sealed = try RemoteSecureChannel.seal(payload, using: secretB)

        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: nil,
            pairedDevices: [deviceA, deviceB]
        )

        guard case .unresolved = resolution else {
            Issue.record("expected unresolved, got \(resolution)")
            return
        }
    }

    @Test("an unknown frame resolves to nothing")
    func unknownFrameResolvesToNothing() {
        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: Data("not-ciphertext".utf8),
            pairingPresharedKey: nil,
            pairedDevices: []
        )
        guard case .unresolved = resolution else {
            Issue.record("expected unresolved, got \(resolution)")
            return
        }
    }

    @Test("a hello frame from an unpaired device resolves to nothing")
    func helloFromUnknownDeviceResolvesToNothing() throws {
        let secret = SymmetricKey(size: .bits256)
        let payload = try RemoteMessageCodec.encode(
            .hello(deviceID: "device-1", protocolVersion: 1)
        )
        let sealed = try RemoteSecureChannel.seal(payload, using: secret)

        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: nil,
            pairedDevices: []
        )

        guard case .unresolved = resolution else {
            Issue.record("expected unresolved, got \(resolution)")
            return
        }
    }

    @Test("a bad pairing-code guess is rejected as pairingKeyRejected, not unresolved")
    func badPairingGuessIsRejected() throws {
        let realKey = RemotePairing.derivePresharedKey(code: "123456")
        let guessedKey = RemotePairing.derivePresharedKey(code: "654321")
        let payload = try RemoteMessageCodec.encode(
            .pairRequest(deviceName: "iPhone", code: "654321")
        )
        // The attacker only knows their own guess, so they can only seal
        // the frame with the key derived from that guess — not the real
        // active code's key the server will try to open it with.
        let sealed = try RemoteSecureChannel.seal(payload, using: guessedKey)

        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: realKey,
            pairedDevices: []
        )

        guard case .pairingKeyRejected = resolution else {
            Issue.record("expected pairingKeyRejected, got \(resolution)")
            return
        }
    }

    @Test("a bad pairing guess that also fails to match any paired device is still pairingKeyRejected, not unresolved")
    func badPairingGuessWithPairedDevicesPresentIsStillRejected() throws {
        let realKey = RemotePairing.derivePresharedKey(code: "123456")
        let guessedKey = RemotePairing.derivePresharedKey(code: "654321")
        let secret = SymmetricKey(size: .bits256)
        let device = RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: secret.withUnsafeBytes { Data($0) }.base64EncodedString(),
            pairedAt: Date()
        )
        let payload = try RemoteMessageCodec.encode(
            .pairRequest(deviceName: "iPhone", code: "654321")
        )
        let sealed = try RemoteSecureChannel.seal(payload, using: guessedKey)

        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: realKey,
            pairedDevices: [device]
        )

        guard case .pairingKeyRejected = resolution else {
            Issue.record("expected pairingKeyRejected, got \(resolution)")
            return
        }
    }

    @Test("a paired device's hello still resolves while a pairing code happens to be active")
    func pairedDeviceHelloResolvesWhilePairingActive() throws {
        let realKey = RemotePairing.derivePresharedKey(code: "123456")
        let secret = SymmetricKey(size: .bits256)
        let device = RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: secret.withUnsafeBytes { Data($0) }.base64EncodedString(),
            pairedAt: Date()
        )
        let payload = try RemoteMessageCodec.encode(
            .hello(deviceID: "device-1", protocolVersion: 1)
        )
        let sealed = try RemoteSecureChannel.seal(payload, using: secret)

        let resolution = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: realKey,
            pairedDevices: [device]
        )

        guard case let .resolved(message, _) = resolution else {
            Issue.record("expected a resolved handshake, got \(resolution)")
            return
        }
        #expect(message == .hello(deviceID: "device-1", protocolVersion: 1))
    }
}
