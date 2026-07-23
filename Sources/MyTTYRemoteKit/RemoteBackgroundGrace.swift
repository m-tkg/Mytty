import Foundation

/// Decides when the iOS app should hold a background-task assertion so a
/// quick app switch does not tear down the live session: iOS suspends an
/// unprotected app almost immediately, killing the Mac connection, while a
/// background task keeps processing alive for the grace period.
///
/// Pure state machine so the double-begin/double-end bookkeeping is
/// testable off-device; the caller maps `.beginProtection` /
/// `.endProtection` onto `UIApplication` begin/endBackgroundTask plus a
/// deadline timer.
public struct RemoteBackgroundGrace: Sendable {
    /// How long processing continues after the app leaves the foreground.
    public static let graceDuration: TimeInterval = 30

    public enum Action: Equatable, Sendable {
        /// Begin the background task and schedule the grace deadline.
        case beginProtection
        /// End the background task and cancel any pending deadline.
        case endProtection
        case none
    }

    public private(set) var isProtecting = false

    public init() {}

    public mutating func sceneDidEnterBackground() -> Action {
        guard !isProtecting else { return .none }
        isProtecting = true
        return .beginProtection
    }

    public mutating func sceneDidActivate() -> Action {
        guard isProtecting else { return .none }
        isProtecting = false
        return .endProtection
    }

    /// The grace deadline passed, or the system called the expiration
    /// handler early; both must release the assertion exactly once.
    public mutating func deadlineExpired() -> Action {
        guard isProtecting else { return .none }
        isProtecting = false
        return .endProtection
    }
}
