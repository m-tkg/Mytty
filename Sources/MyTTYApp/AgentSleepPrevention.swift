import Foundation
import MyTTYCore

struct AgentSleepStatus: Equatable {
    let mode: AgentSleepPreventionMode
    let isActive: Bool
    /// True while `pmset disablesleep` is armed, keeping the Mac awake
    /// even with the lid closed and no external display.
    var keepsLidClosedAwake = false
    /// True while lid-closed keep-awake is wanted but the privileged
    /// helper still needs its one-time approval in System Settings.
    var needsClamshellApproval = false
    /// Registration failure detail for the privileged helper, shown in
    /// the tooltip so a broken install is visible.
    var clamshellHelperIssue: String?

    static let disabled = AgentSleepStatus(mode: .allowSleep, isActive: false)

    var symbolName: String {
        switch mode {
        case .allowSleep:
            "moon"
        case .preventWhileProcessing:
            isActive ? "sun.haze.fill" : "sun.haze"
        case .preventWhileLaunched:
            isActive ? "sun.max.fill" : "sun.max"
        }
    }

    var text: MyTTYText {
        switch (mode, isActive) {
        case (.allowSleep, _):
            .sleepPreventionDisabled
        case (.preventWhileProcessing, false):
            .sleepPreventionEnabled
        case (.preventWhileProcessing, true):
            .sleepPrevented
        case (.preventWhileLaunched, false):
            .sleepPreventionArmedWhileLaunched
        case (.preventWhileLaunched, true):
            .sleepPreventingWhileLaunched
        }
    }

    func tooltip(localizer: MyTTYLocalizer) -> String {
        if keepsLidClosedAwake {
            return localizer[text] + " · "
                + localizer[.sleepClamshellArmedStatus]
        }
        if let clamshellHelperIssue {
            return localizer[text] + " · "
                + localizer[.sleepClamshellRegistrationFailed]
                + " (\(clamshellHelperIssue))"
        }
        if needsClamshellApproval {
            return localizer[text] + " · "
                + localizer[.sleepClamshellApprovalStatus]
        }
        return localizer[text]
    }
}

extension AgentSleepPreventionMode {
    var menuLabel: MyTTYText {
        switch self {
        case .allowSleep: .sleepModeAllowSleep
        case .preventWhileProcessing: .sleepModePreventWhileProcessing
        case .preventWhileLaunched: .sleepModePreventWhileLaunched
        }
    }
}

@MainActor
final class AgentSleepPreventionController {
    private let beginActivity: () -> NSObjectProtocol
    private let endActivity: (NSObjectProtocol) -> Void
    private var activity: NSObjectProtocol?

    private(set) var status: AgentSleepStatus = .disabled

    /// Keeping the display awake is not cosmetic. Ghostty builds each
    /// surface's render loop on a `CVDisplayLink`, and its constructor
    /// binds to the set of *awake* displays: with the screen off there
    /// are none, the call fails, and surface creation fails with it. So
    /// a Mac whose screen has slept cannot open a window, tab, or pane
    /// at all — precisely the state it is in while an agent works
    /// unattended and the iOS remote or `mytty-ctl` asks for a new pane.
    ///
    /// Preventing display sleep alongside system sleep keeps that from
    /// happening for as long as the user has asked us to stay awake.
    nonisolated static let activityOptions: ProcessInfo.ActivityOptions = [
        .idleSystemSleepDisabled,
        .idleDisplaySleepDisabled,
    ]

    init(
        beginActivity: @escaping () -> NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(
                options: AgentSleepPreventionController.activityOptions,
                reason: "An AI agent is processing in Mytty"
            )
        },
        endActivity: @escaping (NSObjectProtocol) -> Void = {
            ProcessInfo.processInfo.endActivity($0)
        }
    ) {
        self.beginActivity = beginActivity
        self.endActivity = endActivity
    }

    func update(
        mode: AgentSleepPreventionMode,
        windowAgentIsActive: [Bool]
    ) {
        guard mode != .allowSleep else {
            endCurrentActivity()
            status = .disabled
            return
        }

        if windowAgentIsActive.contains(true) {
            status = AgentSleepStatus(mode: mode, isActive: true)
            guard activity == nil else { return }
            activity = beginActivity()
        } else {
            endCurrentActivity()
            status = AgentSleepStatus(mode: mode, isActive: false)
        }
    }

    func stop() {
        endCurrentActivity()
        status = .disabled
    }

    private func endCurrentActivity() {
        guard let activity else { return }
        self.activity = nil
        endActivity(activity)
    }
}
