import CryptoKit
import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite("Remote pairing")
struct RemotePairingTests {
    @Test("generates a high-entropy, URL-safe token")
    func generatesHighEntropyToken() {
        let code = RemotePairing.generateCode()
        // 32 bytes base64url-encoded (unpadded) is 43 characters.
        #expect(code.value.count == 43)
        #expect(
            code.value.unicodeScalars.allSatisfy {
                CharacterSet(
                    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                        + "abcdefghijklmnopqrstuvwxyz0123456789-_"
                ).contains($0)
            }
        )
    }

    @Test("generated tokens are random across calls")
    func generatedTokensAreRandom() {
        let first = RemotePairing.generateCode()
        let second = RemotePairing.generateCode()
        #expect(first.value != second.value)
    }

    @Test("code is not expired immediately after generation")
    func codeNotExpiredWhenFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = RemotePairingCode(value: "token-value", generatedAt: now)
        #expect(code.isExpired(at: now) == false)
    }

    @Test("code expires after its validity window")
    func codeExpiresAfterValidityWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = RemotePairingCode(
            value: "token-value",
            generatedAt: now,
            validity: 120
        )
        #expect(code.isExpired(at: now.addingTimeInterval(119)) == false)
        #expect(code.isExpired(at: now.addingTimeInterval(120)) == true)
        #expect(code.isExpired(at: now.addingTimeInterval(121)) == true)
    }

    @Test("deriving a preshared key from the same token is deterministic")
    func derivedKeyIsDeterministicForSameToken() {
        let first = RemotePairing.derivePresharedKey(token: "token-one")
        let second = RemotePairing.derivePresharedKey(token: "token-one")
        #expect(
            first.withUnsafeBytes { Data($0) }
                == second.withUnsafeBytes { Data($0) }
        )
    }

    @Test("deriving a preshared key from different tokens differs")
    func derivedKeyDiffersForDifferentTokens() {
        let first = RemotePairing.derivePresharedKey(token: "token-one")
        let second = RemotePairing.derivePresharedKey(token: "token-two")
        #expect(
            first.withUnsafeBytes { Data($0) }
                != second.withUnsafeBytes { Data($0) }
        )
    }

    @Test("device secrets are random and of the expected length")
    func deviceSecretsAreRandomAndSized() {
        let first = RemotePairing.generateDeviceSecret()
        let second = RemotePairing.generateDeviceSecret()
        #expect(first.count == RemotePairing.deviceSecretByteCount)
        #expect(first != second)
    }
}
