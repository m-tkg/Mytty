import CryptoKit
import Foundation
import MyTTYRemoteKit

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
    ) -> (message: RemoteMessage, key: SymmetricKey)? {
        if let pairingPresharedKey,
           let opened = try? RemoteSecureChannel.open(
               firstFramePayload,
               using: pairingPresharedKey
           ),
           let message = try? RemoteMessageCodec.decode(opened),
           case .pairRequest = message {
            return (message, pairingPresharedKey)
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
            return (message, key)
        }

        return nil
    }
}
