import MyTTYRemoteKit
import UIKit

/// Holds a `UIApplication` background task while the app is in the
/// background so a quick app switch keeps the Mac session processing for
/// `RemoteBackgroundGrace.graceDuration` instead of being suspended (and
/// the connection torn down) almost immediately.
///
/// The begin/end bookkeeping lives in `RemoteBackgroundGrace`; this class
/// only maps its actions onto UIKit.
@MainActor
final class BackgroundSessionKeeper {
    private var grace = RemoteBackgroundGrace()
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private var deadline: Task<Void, Never>?

    func sceneDidEnterBackground() {
        apply(grace.sceneDidEnterBackground())
    }

    func sceneDidActivate() {
        apply(grace.sceneDidActivate())
    }

    private func deadlineExpired() {
        apply(grace.deadlineExpired())
    }

    private func apply(_ action: RemoteBackgroundGrace.Action) {
        switch action {
        case .beginProtection:
            taskID = UIApplication.shared.beginBackgroundTask(
                withName: "RemoteSessionGrace"
            ) { [weak self] in
                // The system may expire the task before our own deadline;
                // release the assertion instead of being killed for
                // overrunning it.
                Task { @MainActor [weak self] in
                    self?.deadlineExpired()
                }
            }
            deadline = Task { [weak self] in
                try? await Task.sleep(
                    for: .seconds(RemoteBackgroundGrace.graceDuration)
                )
                guard !Task.isCancelled else { return }
                self?.deadlineExpired()
            }
        case .endProtection:
            deadline?.cancel()
            deadline = nil
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        case .none:
            break
        }
    }
}
