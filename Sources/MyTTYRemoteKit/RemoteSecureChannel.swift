import CryptoKit
import Foundation

public enum RemoteSecureChannelError: Error, Equatable, Sendable {
    case authenticationFailed
}

/// Seals and opens frame payloads with AES-256-GCM. Successfully opening a
/// frame with a device's stored key is itself proof that the sender
/// possesses that key, so this doubles as the authentication mechanism for
/// paired connections.
public enum RemoteSecureChannel {
    public static func seal(_ payload: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(payload, using: key)
        guard let combined = sealedBox.combined else {
            throw RemoteSecureChannelError.authenticationFailed
        }
        return combined
    }

    public static func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw RemoteSecureChannelError.authenticationFailed
        }
    }
}
