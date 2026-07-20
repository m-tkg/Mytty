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

        let resolved = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: key,
            pairedDevices: []
        )

        guard let resolved else {
            Issue.record("expected a resolved handshake")
            return
        }
        #expect(resolved.message == .pairRequest(deviceName: "iPhone", code: "123456"))
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

        let resolved = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: nil,
            pairedDevices: [device]
        )

        guard let resolved else {
            Issue.record("expected a resolved handshake")
            return
        }
        #expect(
            resolved.message == .hello(deviceID: "device-1", protocolVersion: 1)
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

        let resolved = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: nil,
            pairedDevices: [deviceA, deviceB]
        )

        #expect(resolved == nil)
    }

    @Test("an unknown frame resolves to nothing")
    func unknownFrameResolvesToNothing() {
        let resolved = RemoteHandshakeResolver.resolve(
            firstFramePayload: Data("not-ciphertext".utf8),
            pairingPresharedKey: nil,
            pairedDevices: []
        )
        #expect(resolved == nil)
    }

    @Test("a hello frame from an unpaired device resolves to nothing")
    func helloFromUnknownDeviceResolvesToNothing() throws {
        let secret = SymmetricKey(size: .bits256)
        let payload = try RemoteMessageCodec.encode(
            .hello(deviceID: "device-1", protocolVersion: 1)
        )
        let sealed = try RemoteSecureChannel.seal(payload, using: secret)

        let resolved = RemoteHandshakeResolver.resolve(
            firstFramePayload: sealed,
            pairingPresharedKey: nil,
            pairedDevices: []
        )

        #expect(resolved == nil)
    }
}
