import Foundation

/// XPC interface between the app and the privileged clamshell helper
/// daemon (`mytty-clamshell-helper`). The daemon runs as root via
/// `SMAppService` and is the only place that calls `pmset disablesleep`,
/// so the app never needs an administrator prompt of its own.
@objc public protocol ClamshellHelperXPC {
    /// Turns system-wide sleep disabling on or off. While enabled, the
    /// daemon watches `watchedPID` and restores normal sleep as soon as
    /// that process exits, so a crashed app can never leave the Mac
    /// permanently sleepless. Replies with whether `pmset` succeeded.
    func setKeepAwake(
        _ enabled: Bool,
        watchedPID: Int32,
        reply: @escaping @Sendable (Bool) -> Void
    )
}

/// Naming shared by the app, the helper, and the packaging script: the
/// daemon's launchd label (also its mach service name) is derived from
/// the app bundle identifier, so the release and dev bundles each get
/// their own daemon instead of fighting over one label.
public enum ClamshellHelperService {
    public static func label(bundleIdentifier: String) -> String {
        bundleIdentifier + ".clamshelld"
    }

    public static func plistName(bundleIdentifier: String) -> String {
        label(bundleIdentifier: bundleIdentifier) + ".plist"
    }
}
