import Foundation
import MyTTYCore
import MyTTYRemoteKit

/// Bounds on what a paired device may register, so a malformed or
/// oversized registration is rejected before it is written to disk rather
/// than failing later at send time.
enum RemotePushRegistrationValidation {
    static func isValid(pushID: String, relaySecretBase64: String) -> Bool {
        // The relay issues UUIDs; accepting only those keeps anything
        // odd out of a URL header.
        guard UUID(uuidString: pushID) != nil else { return false }
        guard let secret = Data(base64Encoded: relaySecretBase64),
              secret.count == 32
        else { return false }
        return true
    }
}

/// Fans an Attention item out to every paired iOS device registered for
/// push, sealing the alert with that device's pairing key first. Unlike
/// the live `RemoteAccessServer` channel — which only exists while the app
/// is foregrounded on the same network — this reaches a phone that is
/// asleep, elsewhere, or not running the app at all.
@MainActor
final class RemoteAttentionPushNotifier {
    private let deviceStore: RemotePairedDeviceStore
    private let client: PushRelayClient
    private var localizer: MyTTYLocalizer
    private let isEnabled: () -> Bool
    private let hostName: () -> String?
    private let onError: (Error) -> Void

    init(
        deviceStore: RemotePairedDeviceStore,
        client: PushRelayClient = PushRelayClient(),
        localizer: MyTTYLocalizer,
        isEnabled: @escaping () -> Bool,
        hostName: @escaping () -> String? = { Host.current().localizedName },
        onError: @escaping (Error) -> Void
    ) {
        self.deviceStore = deviceStore
        self.client = client
        self.localizer = localizer
        self.isEnabled = isEnabled
        self.hostName = hostName
        self.onError = onError
    }

    func updateLocalization(_ localizer: MyTTYLocalizer) {
        self.localizer = localizer
    }

    func notify(_ item: AttentionItem, tabTitle: String?) {
        guard isEnabled(), let devices = try? deviceStore.load() else { return }
        let targets = devices.compactMap(PushRelayTarget.init(device:))
        guard !targets.isEmpty else { return }

        let localizedBody = item.notificationBody(localizer: localizer)
        // A phone-side banner has no idea which Mac or which tab an agent
        // is waiting in, unlike the in-app banner (which the user is
        // already looking at the window for) — so the push spells both
        // out as a leading context line, skipping whichever part is
        // unavailable.
        let context = [hostName(), tabTitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let body = context.isEmpty
            ? localizedBody
            : "\(context)\n\(localizedBody)"

        let alert = PushRelayAlert(
            title: item.kind.notificationTitle(localizer: localizer),
            body: body,
            paneID: item.surfaceID.rawValue.uuidString
        )
        // Collapsing per surface keeps a chatty pane to a single banner
        // while still letting other panes through.
        let collapseID = item.surfaceID.rawValue.uuidString

        let client = self.client
        let onError = self.onError
        Task {
            for target in targets {
                do {
                    try await client.send(
                        alert,
                        to: target,
                        collapseID: collapseID
                    )
                } catch {
                    // One unreachable phone must not stop the others.
                    await MainActor.run { onError(error) }
                }
            }
        }
    }
}
