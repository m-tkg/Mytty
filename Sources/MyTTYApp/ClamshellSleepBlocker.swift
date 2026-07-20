import Foundation
import MyTTYCore
import ServiceManagement

/// Abstraction over the privileged clamshell daemon so the blocker's
/// decision logic is testable without ServiceManagement or XPC.
@MainActor
protocol ClamshellDaemonControlling: AnyObject {
    /// The daemon is registered and approved; XPC calls will reach root.
    var isApproved: Bool { get }
    /// Registration happened but the user must allow the background item
    /// in System Settings before the daemon may run.
    var requiresApproval: Bool { get }
    /// Human-readable description of the last registration failure,
    /// nil when registration succeeded or was never needed.
    var registrationErrorDescription: String? { get }
    func registerIfNeeded()
    func openApprovalSettings()
    func setKeepAwake(
        _ enabled: Bool,
        watchedPID: pid_t,
        completion: @escaping @MainActor (Bool) -> Void
    )
}

/// Keeps the Mac awake with the lid closed and no external display.
/// Sleep assertions cannot stop clamshell sleep; the only supported
/// switch is `pmset disablesleep`, which needs root. The blocker follows
/// the app's sleep-prevention state (`setDesired`) rather than being a
/// user-toggled feature of its own.
///
/// Preferred path: the bundled `mytty-clamshell-helper` daemon
/// (SMAppService) runs `pmset` as root after a one-time approval in
/// System Settings — no password prompts, ever. The daemon watches the
/// app's PID and restores normal sleep if Mytty dies.
///
/// Fallback (running outside an app bundle, e.g. `swift run`): an
/// AppleScript administrator prompt starts a root watcher script once
/// per app run; the watcher follows a flag file so re-arming needs no
/// new prompt.
@MainActor
final class ClamshellSleepBlocker {
    private(set) var isArmed = false
    /// True while lid-closed keep-awake is wanted but blocked on the
    /// user approving Mytty's background item in System Settings.
    private(set) var needsBackgroundItemApproval = false
    /// Fired whenever `isArmed` or `needsBackgroundItemApproval` change.
    var onChange: (() -> Void)?
    /// Registration failure detail from the daemon, surfaced in the
    /// status tooltip so a broken install isn't silently ignored.
    var registrationErrorDescription: String? {
        daemon?.registrationErrorDescription
    }

    /// Asks the user before System Settings opens for the one-time
    /// background-item approval, so the auth sheet never appears out of
    /// nowhere. Returning false skips opening Settings. When unset, the
    /// approval settings open directly.
    var confirmApprovalPrompt: (() -> Bool)?

    private let daemon: ClamshellDaemonControlling?
    private let flagURL: URL
    private let watchedPID: pid_t
    private let runPrivileged: (String) -> Bool
    /// Fallback only: true once a root watcher for this app run has been
    /// started; while it is alive, arming again just recreates the flag.
    private var hasLiveWatcher = false
    /// Fallback only: the user cancelled the password prompt; stop
    /// asking until they change the sleep mode again.
    private var promptDeclined = false

    private var desired = false
    private var requestedOfDaemon: Bool?
    private var requestInFlight = false
    /// Set when the next blocked apply comes from an explicit user
    /// action (mode selection) and may open System Settings.
    private var pendingUserIntent = false

    init(
        flagURL: URL,
        watchedPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        daemon: ClamshellDaemonControlling? = nil,
        runPrivileged: ((String) -> Bool)? = nil
    ) {
        self.flagURL = flagURL
        self.watchedPID = watchedPID
        self.daemon = daemon ?? Self.bundledDaemonClient()
        self.runPrivileged = runPrivileged
            ?? Self.runWithAdministratorPrivileges
        // A leftover flag from an earlier run has no watcher attached to
        // it (the watcher restores and exits when the old process dies);
        // every session starts disarmed.
        try? FileManager.default.removeItem(at: flagURL)
    }

    /// Registers the daemon at launch so the one-time System Settings
    /// approval can happen before it is first needed.
    func prepare() {
        daemon?.registerIfNeeded()
    }

    /// Marks the next apply as user-initiated: if approval is missing,
    /// System Settings opens so the user can grant it in context.
    func noteUserIntent() {
        pendingUserIntent = true
    }

    /// Follows the app's sleep-prevention state: keep the lid-closed
    /// override armed exactly while sleep prevention is in effect.
    func setDesired(keepAwake: Bool) {
        desired = keepAwake
        apply()
    }

    private func apply() {
        if let daemon {
            applyViaDaemon(daemon)
        } else {
            applyViaFallback()
        }
    }

    // MARK: Daemon path

    private func applyViaDaemon(_ daemon: ClamshellDaemonControlling) {
        guard !requestInFlight else { return }
        if daemon.isApproved {
            setApprovalNeeded(false)
            guard requestedOfDaemon != desired else { return }
            let requested = desired
            requestInFlight = true
            daemon.setKeepAwake(requested, watchedPID: watchedPID) {
                [weak self] success in
                guard let self else { return }
                self.requestInFlight = false
                if success {
                    self.requestedOfDaemon = requested
                    self.setArmed(requested)
                } else {
                    self.requestedOfDaemon = nil
                    self.setArmed(false)
                }
                if self.desired != requested {
                    self.apply()
                }
            }
            return
        }
        daemon.registerIfNeeded()
        setArmed(false)
        // Not gated on `desired`: a prevention mode with no agent open
        // yet should still surface the pending approval.
        setApprovalNeeded(daemon.requiresApproval)
        if pendingUserIntent {
            pendingUserIntent = false
            if daemon.requiresApproval,
               confirmApprovalPrompt?() ?? true {
                daemon.openApprovalSettings()
            }
        }
    }

    // MARK: Fallback path (no bundle, e.g. `swift run`)

    private func applyViaFallback() {
        if desired {
            guard !isArmed else { return }
            if pendingUserIntent {
                pendingUserIntent = false
                promptDeclined = false
            }
            guard !promptDeclined else { return }
            try? FileManager.default.createDirectory(
                at: flagURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(
                atPath: flagURL.path,
                contents: nil
            )
            if !hasLiveWatcher {
                let script = Self.watcherScript(
                    flagPath: flagURL.path,
                    watchedPID: watchedPID
                )
                guard runPrivileged(script) else {
                    try? FileManager.default.removeItem(at: flagURL)
                    promptDeclined = true
                    return
                }
                hasLiveWatcher = true
            }
            setArmed(true)
        } else {
            try? FileManager.default.removeItem(at: flagURL)
            setArmed(false)
        }
    }

    // MARK: State

    private func setArmed(_ armed: Bool) {
        guard isArmed != armed else { return }
        isArmed = armed
        onChange?()
    }

    private func setApprovalNeeded(_ needed: Bool) {
        guard needsBackgroundItemApproval != needed else { return }
        needsBackgroundItemApproval = needed
        onChange?()
    }

    // MARK: Real dependencies

    private static func bundledDaemonClient() -> ClamshellDaemonControlling? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let identifier = Bundle.main.bundleIdentifier,
              identifier.hasPrefix("com.m-tkg.mytty")
        else { return nil }
        return ClamshellDaemonClient(bundleIdentifier: identifier)
    }

    /// The root-side fallback watcher: follow the flag file — present
    /// means `disablesleep 1`, absent means `disablesleep 0`, invoking
    /// `pmset` only when that changes — until the watched process exits,
    /// then restore and clean up the flag.
    nonisolated static func watcherScript(
        flagPath: String,
        watchedPID: pid_t,
        pollSeconds: Double = 2
    ) -> String {
        let inner = "current=; "
            + "while kill -0 \(watchedPID) 2>/dev/null; do "
            + "if [ -e \"\(flagPath)\" ]; then want=1; else want=0; fi; "
            + "if [ \"$want\" != \"$current\" ]; then "
            + "pmset disablesleep $want; current=$want; fi; "
            + "sleep \(pollSeconds); done; "
            + "pmset disablesleep 0; rm -f \"\(flagPath)\""
        return "nohup /bin/sh -c '\(inner)' >/dev/null 2>&1 &"
    }

    private static func runWithAdministratorPrivileges(
        _ shellScript: String
    ) -> Bool {
        let escaped = shellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source =
            "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}

/// The real daemon client: SMAppService registration plus the XPC
/// connection to `mytty-clamshell-helper`.
@MainActor
private final class ClamshellDaemonClient: ClamshellDaemonControlling {
    private let label: String
    private let service: SMAppService
    private var connection: NSXPCConnection?

    init(bundleIdentifier: String) {
        label = ClamshellHelperService.label(
            bundleIdentifier: bundleIdentifier
        )
        service = SMAppService.daemon(
            plistName: ClamshellHelperService.plistName(
                bundleIdentifier: bundleIdentifier
            )
        )
    }

    var isApproved: Bool { service.status == .enabled }

    var requiresApproval: Bool { service.status == .requiresApproval }

    private(set) var registrationErrorDescription: String?

    func registerIfNeeded() {
        guard service.status == .notRegistered
            || service.status == .notFound
        else { return }
        do {
            try service.register()
            registrationErrorDescription = nil
        } catch {
            registrationErrorDescription = error.localizedDescription
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setKeepAwake(
        _ enabled: Bool,
        watchedPID: pid_t,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let deliver = DeliverOnce(completion)
        guard let proxy = xpcProxy(onError: {
            Task { @MainActor in deliver.run(false) }
        }) else {
            deliver.run(false)
            return
        }
        proxy.setKeepAwake(enabled, watchedPID: watchedPID) { success in
            Task { @MainActor in deliver.run(success) }
        }
    }

    private func xpcProxy(
        onError: @escaping @Sendable () -> Void
    ) -> ClamshellHelperXPC? {
        if connection == nil {
            let connection = NSXPCConnection(
                machServiceName: label,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(
                with: ClamshellHelperXPC.self
            )
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.connection = nil
                }
            }
            connection.resume()
            self.connection = connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in
            onError()
        } as? ClamshellHelperXPC
    }
}

/// XPC reply and error handlers can both fire; collapse them into a
/// single main-actor completion call.
private final class DeliverOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@MainActor (Bool) -> Void)?

    init(_ completion: @escaping @MainActor (Bool) -> Void) {
        self.completion = completion
    }

    @MainActor
    func run(_ success: Bool) {
        lock.lock()
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(success)
    }
}
