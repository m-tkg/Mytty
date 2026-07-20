import AppKit
import Foundation

/// Owns the self-update flow: the `ApplicationUpdateModel` (and the
/// ephemeral `URLSession` it's built on), the launch/About check trigger,
/// and the confirmation/restart alerts. AppDelegate keeps the localizer
/// (it changes with the user's language preference) and the generic
/// action-error alert, so both are threaded through as closures evaluated
/// at call time rather than captured once.
@MainActor
final class ApplicationUpdateCoordinator {
    private lazy var updateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    lazy var model: ApplicationUpdateModel = ApplicationUpdateModel(
        currentVersion: ApplicationIdentity.version,
        checker: GitHubReleaseClient(session: updateSession),
        installer: ApplicationUpdateInstaller(session: updateSession),
        confirmsInstallation: { [weak self] in
            self?.confirmUpdateInstallation() ?? false
        },
        onInstalled: { [weak self] in
            self?.restartAfterUpdate()
        }
    )

    private let localizerProvider: () -> MyTTYLocalizer
    private let presentActionError: (Error) -> Void

    init(
        localizerProvider: @escaping () -> MyTTYLocalizer,
        presentActionError: @escaping (Error) -> Void
    ) {
        self.localizerProvider = localizerProvider
        self.presentActionError = presentActionError
    }

    func checkForUpdates(trigger: ApplicationUpdateCheckTrigger) {
        guard ApplicationIdentity.supportsSelfUpdate else { return }
        let automation = ApplicationUpdateAutomation(model: model)
        Task {
            await automation.check(trigger: trigger)
        }
    }

    private func confirmUpdateInstallation() -> Bool {
        let localizer = localizerProvider()
        let alert = ApplicationAlert.make(style: .warning)
        alert.messageText = localizer[.installUpdateQuestion]
        alert.informativeText = localizer[.restartForUpdateWarning]
        alert.addButton(withTitle: localizer[.update])
        alert.addButton(withTitle: localizer[.cancel])
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func restartAfterUpdate() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "/bin/sleep 1; exec /usr/bin/open -n \"$1\"",
            "mytty-update",
            Bundle.main.bundleURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            presentActionError(error)
        }
    }
}
