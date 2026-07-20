import CryptoKit
import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite("Remote secure channel")
struct RemoteSecureChannelTests {
    @Test("seals and opens a payload with the same key")
    func sealsAndOpensRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let payload = Data("hello pane".utf8)

        let sealed = try RemoteSecureChannel.seal(payload, using: key)
        let opened = try RemoteSecureChannel.open(sealed, using: key)

        #expect(opened == payload)
    }

    @Test("opening with the wrong key fails authentication")
    func openingWithWrongKeyFails() throws {
        let key = SymmetricKey(size: .bits256)
        let otherKey = SymmetricKey(size: .bits256)
        let payload = Data("hello pane".utf8)

        let sealed = try RemoteSecureChannel.seal(payload, using: key)

        #expect(throws: RemoteSecureChannelError.authenticationFailed) {
            _ = try RemoteSecureChannel.open(sealed, using: otherKey)
        }
    }

    @Test("tampering with ciphertext is detected")
    func tamperingIsDetected() throws {
        let key = SymmetricKey(size: .bits256)
        var sealed = try RemoteSecureChannel.seal(Data("hello".utf8), using: key)
        sealed[sealed.count - 1] ^= 0xFF

        #expect(throws: RemoteSecureChannelError.authenticationFailed) {
            _ = try RemoteSecureChannel.open(sealed, using: key)
        }
    }

    @Test("sealing the same payload twice yields different ciphertext")
    func sealingIsNonDeterministic() throws {
        let key = SymmetricKey(size: .bits256)
        let payload = Data("hello".utf8)

        let first = try RemoteSecureChannel.seal(payload, using: key)
        let second = try RemoteSecureChannel.seal(payload, using: key)

        #expect(first != second)
    }
}
