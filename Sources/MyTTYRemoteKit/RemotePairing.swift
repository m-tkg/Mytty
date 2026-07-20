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
    private static let pairingSalt = Data("mytty-pairing-v1".utf8)
    private static let pairingInfo = Data("mytty-pairing-psk".utf8)

    public static func generateCode(
        generatedAt: Date = Date(),
        randomDigit: () -> Int = { Int.random(in: 0...9) }
    ) -> RemotePairingCode {
        let digits = (0..<6).map { _ in String(randomDigit()) }.joined()
        return RemotePairingCode(value: digits, generatedAt: generatedAt)
    }

    /// Derives a pre-shared key from a short pairing code so the initial
    /// pairing handshake can be encrypted without exchanging a secret
    /// out-of-band beyond the code the user types in.
    public static func derivePresharedKey(code: String) -> SymmetricKey {
        let codeKey = SymmetricKey(data: Data(code.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: codeKey,
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
