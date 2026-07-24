import CryptoKit
import Foundation

public struct RemotePairingCode: Equatable, Sendable {
    public let value: String
    public let generatedAt: Date
    public let expiresAt: Date

    public init(
        value: String,
        generatedAt: Date = Date(),
        validity: TimeInterval = RemotePairing.codeValidity
    ) {
        self.value = value
        self.generatedAt = generatedAt
        self.expiresAt = generatedAt.addingTimeInterval(validity)
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expiresAt
    }
}

public enum RemotePairing {
    public static let codeValidity: TimeInterval = 120
    public static let deviceSecretByteCount = 32
    /// 256 bits of entropy for the pairing token carried in the Mac's QR
    /// code. This replaced a 6-digit typed code (~20 bits): an attacker
    /// who passively captures the pairing handshake could brute-force all
    /// one million 6-digit values offline in milliseconds and recover the
    /// device secret sealed with the derived key. A token this size makes
    /// that infeasible.
    public static let tokenByteCount = 32
    private static let pairingSalt = Data("mytty-pairing-v1".utf8)
    private static let pairingInfo = Data("mytty-pairing-psk".utf8)

    /// Generates the high-entropy pairing token shown (as a QR code) in
    /// Settings. `randomBytes` is injectable for tests; production callers
    /// get cryptographically random bytes via `CryptoKit.SymmetricKey`.
    public static func generateCode(
        generatedAt: Date = Date(),
        randomBytes: (Int) -> Data = { count in
            SymmetricKey(size: SymmetricKeySize(bitCount: count * 8))
                .withUnsafeBytes { Data($0) }
        }
    ) -> RemotePairingCode {
        let token = randomBytes(tokenByteCount).base64URLEncodedString()
        return RemotePairingCode(value: token, generatedAt: generatedAt)
    }

    /// Derives a pre-shared key from the pairing token so the initial
    /// pairing handshake can be encrypted without exchanging a secret
    /// out-of-band beyond the token the QR code carries.
    public static func derivePresharedKey(token: String) -> SymmetricKey {
        let tokenKey = SymmetricKey(data: Data(token.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: tokenKey,
            salt: pairingSalt,
            info: pairingInfo,
            outputByteCount: SHA256.byteCount
        )
    }

    public static func generateDeviceSecret() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func generateDeviceID() -> String {
        UUID().uuidString
    }
}

extension Data {
    /// RFC 4648 §5 base64url, unpadded, so a pairing token can ride in a
    /// URL query string (and therefore a QR code) without percent-encoding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
