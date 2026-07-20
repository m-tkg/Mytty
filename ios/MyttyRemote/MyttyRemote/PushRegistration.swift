import Foundation
import MyTTYRemoteKit
import Security
import UIKit
import UserNotifications

/// What the relay hands back in exchange for an APNs device token. The
/// Mac is given only this: it never learns the device token, and the
/// relay never learns the pairing key the alert text is sealed with.
struct PushRelayRegistration: Codable, Equatable {
    var pushID: String
    var relaySecret: String
    /// The device token this registration was issued for, so a relaunch
    /// that yields the same token reuses it instead of registering again.
    var deviceToken: String
}

/// Owns this device's push setup: the notification permission, the APNs
/// token, and the relay registration derived from it. `RemoteClient`
/// forwards the registration to every Mac it connects to.
@MainActor
final class PushRegistration: NSObject, ObservableObject {
    static let shared = PushRegistration()

    @Published private(set) var registration: PushRelayRegistration?
    @Published private(set) var isAuthorized = false
    /// Set when the user taps an Attention notification, and cleared once
    /// the UI has navigated. Held here rather than delivered directly
    /// because the tap usually arrives before there is any view to act on
    /// it — a cold launch from the Lock Screen runs this delegate first.
    @Published var pendingOpen: PushNotificationTarget?

    /// A sandbox token is rejected outright by the production APNs host
    /// and vice versa, so this is read from the entitlement the running
    /// binary was actually signed with rather than assumed from `#if
    /// DEBUG` — a Release build run from Xcode is still a sandbox build.
    let environment: String = PushEnvironmentResolver.current()

    private let session: URLSession
    private let baseURL: URL

    private init(
        session: URLSession = .shared,
        baseURL: URL = PushRelay.defaultURL
    ) {
        self.session = session
        self.baseURL = baseURL
        super.init()
        registration = PushRelayRegistrationStore.load()
    }

    /// Asks for permission (iOS ignores repeat prompts) and, if granted,
    /// registers with APNs. Declining leaves `registration` nil, which
    /// simply means this device is never pushed to.
    func register() {
        Task {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .notDetermined:
                isAuthorized = (try? await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )) ?? false
            case .denied:
                isAuthorized = false
            @unknown default:
                isAuthorized = false
            }
            guard isAuthorized else {
                // Revoking permission must reach the Mac, or it keeps
                // pushing into a void.
                clearRegistration()
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Always re-registers, rather than trusting a stored registration
    /// that still matches this device token. The relay drops a
    /// registration the moment APNs calls its token dead, and nothing
    /// tells the phone that happened — so a cached registration can be
    /// silently defunct, and reusing it would leave push broken for good
    /// with no way back. One request per launch is a cheap way to be
    /// self-healing instead.
    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await exchangeWithRelay(deviceToken: token) }
    }

    func didFailToRegister() {
        clearRegistration()
    }

    private func exchangeWithRelay(deviceToken: String) async {
        var request = URLRequest(url: PushRelay.registerURL(base: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceToken": deviceToken,
            "environment": environment,
        ])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let issued = try? JSONDecoder().decode(
                  RelayRegistrationResponse.self,
                  from: data
              )
        else { return }

        let registration = PushRelayRegistration(
            pushID: issued.pushID,
            relaySecret: issued.relaySecret,
            deviceToken: deviceToken
        )
        PushRelayRegistrationStore.save(registration)
        self.registration = registration
    }

    private func clearRegistration() {
        guard registration != nil else { return }
        PushRelayRegistrationStore.clear()
        registration = nil
    }

    private struct RelayRegistrationResponse: Decodable {
        let pushID: String
        let relaySecret: String
    }
}

/// What an Attention notification points at. The pane is absent when the
/// service extension could not decrypt the alert, in which case opening
/// the Mac's session is still better than opening nothing.
struct PushNotificationTarget: Equatable {
    let macID: String
    let paneID: String?
}

extension PushRegistration: UNUserNotificationCenterDelegate {
    /// Attention alerts matter most when the app happens to be open on
    /// another pane, so show them rather than swallowing them.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else { return }
        let userInfo = response.notification.request.content.userInfo
        guard let macID = userInfo["m"] as? String else { return }
        let paneID = userInfo["paneID"] as? String
        await MainActor.run {
            self.pendingOpen = PushNotificationTarget(
                macID: macID,
                paneID: paneID
            )
        }
    }
}

/// Keychain storage for the relay registration, in the same shared access
/// group as the paired Macs so it survives reinstall-free app updates.
enum PushRelayRegistrationStore {
    private static let service = "dev.mytty.remote.push-relay"
    private static let account = "relay-registration"

    static func load() -> PushRelayRegistration? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result)
                == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(
            PushRelayRegistration.self,
            from: data
        )
    }

    static func save(_ registration: PushRelayRegistration) {
        guard let data = try? JSONEncoder().encode(registration) else { return }
        SecItemDelete(baseQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Reads `aps-environment` out of the provisioning profile embedded in the
/// app bundle. App Store builds ship without a profile, and those are
/// always production.
enum PushEnvironmentResolver {
    static func current() -> String {
        guard let url = Bundle.main.url(
            forResource: "embedded",
            withExtension: "mobileprovision"
        ), let data = try? Data(contentsOf: url) else { return "production" }
        return environment(fromProfile: data)
    }

    /// The profile is CMS-signed binary with an XML plist in the middle,
    /// so the plist is sliced out by its delimiters rather than decoded.
    static func environment(fromProfile data: Data) -> String {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(
                  of: Data("</plist>".utf8),
                  in: start.lowerBound..<data.endIndex
              )
        else { return "production" }
        let plist = data[start.lowerBound..<end.upperBound]
        guard let object = try? PropertyListSerialization.propertyList(
            from: plist,
            format: nil
        ),
            let profile = object as? [String: Any],
            let entitlements = profile["Entitlements"] as? [String: Any],
            let value = entitlements["aps-environment"] as? String
        else { return "production" }
        // Apple spells the sandbox one "development" in the entitlement
        // but "sandbox" in the APNs host; normalise to our wire value.
        return value == "development" ? "sandbox" : "production"
    }
}
