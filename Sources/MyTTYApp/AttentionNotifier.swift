import MyTTYCore
import UserNotifications

@MainActor
final class AttentionNotifier: NSObject {
    private static let surfaceIDKey = "surfaceID"

    private let center: UNUserNotificationCenter
    private var localizer: MyTTYLocalizer
    private let onFocus: (TerminalSurfaceID) -> Void
    private let onError: (Error) -> Void

    init(
        center: UNUserNotificationCenter = .current(),
        localizer: MyTTYLocalizer,
        onFocus: @escaping (TerminalSurfaceID) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.center = center
        self.localizer = localizer
        self.onFocus = onFocus
        self.onError = onError
        super.init()
        center.delegate = self
    }

    func notify(_ item: AttentionItem) {
        let content = UNMutableNotificationContent()
        content.title = item.kind.notificationTitle(localizer: localizer)
        content.body = item.message
            ?? item.kind.notificationBody(localizer: localizer)
        content.sound = .default
        content.userInfo = [
            Self.surfaceIDKey: item.surfaceID.rawValue.uuidString,
        ]
        let request = UNNotificationRequest(
            identifier: item.id.rawValue.uuidString,
            content: content,
            trigger: nil
        )

        Task {
            do {
                let settings = await center.notificationSettings()
                let authorized: Bool
                switch settings.authorizationStatus {
                case .authorized,
                     .provisional,
                     .ephemeral:
                    authorized = true
                case .notDetermined:
                    authorized = try await center.requestAuthorization(
                        options: [.alert, .sound]
                    )
                case .denied:
                    authorized = false
                @unknown default:
                    authorized = false
                }
                if authorized {
                    try await center.add(request)
                }
            } catch {
                onError(error)
            }
        }
    }

    func updateLocalization(_ localizer: MyTTYLocalizer) {
        self.localizer = localizer
    }
}

extension AttentionNotifier: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier
                == UNNotificationDefaultActionIdentifier,
              let rawValue = response.notification.request.content
                .userInfo[Self.surfaceIDKey] as? String,
              let identifier = UUID(uuidString: rawValue)
        else { return }

        onFocus(TerminalSurfaceID(rawValue: identifier))
    }
}

/// Shared with `RemoteAttentionPushNotifier` so a Mac banner and the iOS
/// push for the same Attention item always read identically.
extension AttentionItemKind {
    func notificationTitle(localizer: MyTTYLocalizer) -> String {
        switch self {
        case .approvalRequest: localizer[.approvalRequested]
        case .inputRequest: localizer[.inputRequested]
        case .failure: localizer[.agentFailed]
        case .disconnected: localizer[.agentDisconnected]
        case .completion: localizer[.workCompleted]
        }
    }

    func notificationBody(localizer: MyTTYLocalizer) -> String {
        switch self {
        case .approvalRequest: localizer[.approvalFallback]
        case .inputRequest: localizer[.inputFallback]
        case .failure: localizer[.failureFallback]
        case .disconnected: localizer[.disconnectedFallback]
        case .completion: localizer[.completionFallback]
        }
    }
}
