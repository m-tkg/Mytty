import CryptoKit
import Foundation
import MyTTYRemoteKit
import UserNotifications

/// Decrypts Attention alerts before iOS displays them.
///
/// The relay only ever carries ciphertext, so the payload that arrives
/// here has a deliberately vague placeholder as its visible text. This
/// extension unseals the real title and body with the pairing key the Mac
/// and this phone established, reading it from the Keychain group shared
/// with the app.
///
/// If anything fails — an unpaired Mac, a rotated key, a payload from a
/// newer app — the placeholder stands. A vague notification is a far
/// better outcome than a silent one.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler:
            @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = request.content.mutableCopy()
            as? UNMutableNotificationContent
        bestAttempt = content
        defer { contentHandler(bestAttempt ?? request.content) }

        guard let content,
              let macID = request.content.userInfo["m"] as? String,
              let ciphertext = request.content.userInfo["c"] as? String,
              let sealed = Data(base64Encoded: ciphertext),
              let mac = PairedMacStore.loadAll()
                  .first(where: { $0.deviceID == macID }),
              let opened = try? RemoteSecureChannel.open(
                  sealed,
                  using: SymmetricKey(data: mac.deviceSecret)
              ),
              let alert = try? JSONDecoder().decode(
                  PushRelayAlert.self,
                  from: opened
              )
        else { return }

        content.title = alert.title
        content.body = alert.body
        // Naming the Mac matters as soon as more than one is paired, and
        // the phone is the only side that knows the label the user chose.
        if !mac.displayName.isEmpty {
            content.subtitle = mac.displayName
        }
        if let paneID = alert.paneID {
            content.userInfo["paneID"] = paneID
        }
    }

    /// iOS gives the extension a limited budget; deliver the placeholder
    /// rather than letting the notification be dropped.
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt {
            contentHandler(bestAttempt)
        }
    }
}

/// The sealed payload, mirroring the Mac's `PushRelayAlert`.
struct PushRelayAlert: Codable, Equatable {
    var title: String
    var body: String
    var paneID: String?
}
