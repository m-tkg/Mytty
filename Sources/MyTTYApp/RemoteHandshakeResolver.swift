import CryptoKit
import Foundation
import MyTTYRemoteKit

/// The outcome of trying to identify and authenticate the first frame on a
/// new remote connection.
enum RemoteHandshakeResolution {
    /// The frame decrypted and decoded as either a pairing request against
    /// the active pairing code, or a hello from an already-paired device.
    case resolved(message: RemoteMessage, key: SymmetricKey)
    /// A pairing code was active and its derived key was tried against the
    /// frame, but the frame could not be opened/decoded as a `pairRequest`
    /// with it, and it also didn't match any paired device. This is the
    /// signature of an online guess at the six digit code: the guesser's
    /// key doesn't match the real one, so decryption fails.
    case pairingKeyRejected
    /// No pairing code was active, or the frame matched neither the
    /// pairing key nor any paired device — not a pairing attempt at all.
    case unresolved
}

/// Every frame on a remote connection is AES-GCM ciphertext; there is no
/// cleartext identity on the wire. The first frame is opaque until it is
/// successfully decrypted, which is what identifies (and authenticates)
/// the sender: the active pairing code's derived key for a new device, or
/// one of the already-paired devices' secrets for a returning one.
enum RemoteHandshakeResolver {
    static func resolve(
        firstFramePayload: Data,
        pairingPresharedKey: SymmetricKey?,
        pairedDevices: [RemotePairedDevice]
    ) -> RemoteHandshakeResolution {
        if let pairingPresharedKey,
           let opened = try? RemoteSecureChannel.open(
               firstFramePayload,
               using: pairingPresharedKey
           ),
           let message = try? RemoteMessageCodec.decode(opened),
           case .pairRequest = message {
            return .resolved(message: message, key: pairingPresharedKey)
        }

        for device in pairedDevices {
            guard let secretData = Data(base64Encoded: device.secretBase64)
            else { continue }
            let key = SymmetricKey(data: secretData)
            guard let opened = try? RemoteSecureChannel.open(
                firstFramePayload,
                using: key
            ),
                let message = try? RemoteMessageCodec.decode(opened),
                case let .hello(deviceID, _) = message,
                deviceID == device.id
            else { continue }
            return .resolved(message: message, key: key)
        }

        return pairingPresharedKey != nil ? .pairingKeyRejected : .unresolved
    }
}
