import SwiftUI
import UIKit
import UserNotifications

@main
struct MyttyRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundKeeper = BackgroundSessionKeeper()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundKeeper.sceneDidEnterBackground()
            case .active:
                backgroundKeeper.sceneDidActivate()
            default:
                break
            }
        }
    }
}

/// Only exists to receive the APNs token: UIKit delivers it through the
/// application delegate, which SwiftUI has no equivalent of.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The notification delegate has to be in place before launch
    /// finishes: tapping an alert from the Lock Screen starts the app and
    /// delivers the response immediately, and a delegate installed any
    /// later never hears about it.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushRegistration.shared
        // Items written by older builds are unreadable while the phone is
        // locked, which left the notification extension showing the vague
        // placeholder instead of the decrypted alert.
        PairedMacStore.migrateForLockedDeviceAccess()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistration.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushRegistration.shared.didFailToRegister()
        }
    }
}
