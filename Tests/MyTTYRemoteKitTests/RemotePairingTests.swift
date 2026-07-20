import CryptoKit
import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite("Remote pairing")
struct RemotePairingTests {
    @Test("generates a six digit code")
    func generatesSixDigitCode() {
        let code = RemotePairing.generateCode()
        #expect(code.value.count == 6)
        #expect(code.value.allSatisfy { $0.isNumber })
    }

    @Test("code is not expired immediately after generation")
    func codeNotExpiredWhenFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = RemotePairingCode(value: "123456", generatedAt: now)
        #expect(code.isExpired(at: now) == false)
    }

    @Test("code expires after its validity window")
    func codeExpiresAfterValidityWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = RemotePairingCode(
            value: "123456",
            generatedAt: now,
            validity: 120
        )
        #expect(code.isExpired(at: now.addingTimeInterval(119)) == false)
        #expect(code.isExpired(at: now.addingTimeInterval(120)) == true)
        #expect(code.isExpired(at: now.addingTimeInterval(121)) == true)
    }

    @Test("deriving a preshared key from the same code is deterministic")
    func derivedKeyIsDeterministicForSameCode() {
        let first = RemotePairing.derivePresharedKey(code: "123456")
        let second = RemotePairing.derivePresharedKey(code: "123456")
        #expect(
            first.withUnsafeBytes { Data($0) }
                == second.withUnsafeBytes { Data($0) }
        )
    }

    @Test("deriving a preshared key from different codes differs")
    func derivedKeyDiffersForDifferentCodes() {
        let first = RemotePairing.derivePresharedKey(code: "123456")
        let second = RemotePairing.derivePresharedKey(code: "654321")
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
