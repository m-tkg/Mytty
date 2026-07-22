import Foundation
import MyTTYCore

/// Owns the in-memory `mytty-ctl agent` job registry: creates worker panes,
/// tracks each spawn's `AgentJobTracker`, and answers every
/// `ControlServerAgentDelegate` call by resolving a job ID to a pane and
/// (re)reconciling against `AttentionCenter`. Not persisted — see
/// `AgentJobTracker`'s documentation for why that's fine for version 1.
///
/// Mirrors `ControlCoordinator`'s relationship to pane operations, but kept
/// as its own type (per `docs/explanation/mytty-ctl-architecture.md`)
/// because job state needs its own registry and reconciliation step that
/// plain pane operations don't.
@MainActor
final class AgentJobCoordinator {
    private var trackers: [AgentJobID: AgentJobTracker] = [:]

    private let windowSessionCoordinator: WindowSessionCoordinator
    private let attentionCenter: AttentionCenter
    private let integrationStatus: (AgentProvider) -> AgentIntegrationStatus
    private let now: () -> Date
    private let launchWindow: TimeInterval

    /// Label validation mirrors the other short free-text fields Mytty
    /// already accepts from hook payloads — see `AgentSessionValidation` —
    /// scaled down since a label is purely a human/orchestrator mnemonic.
    private static let maximumLabelScalars = 100

    init(
        windowSessionCoordinator: WindowSessionCoordinator,
        attentionCenter: AttentionCenter,
        integrationStatus: @escaping (AgentProvider) -> AgentIntegrationStatus,
        now: @escaping () -> Date = Date.init,
        launchWindow: TimeInterval = 30
    ) {
        self.windowSessionCoordinator = windowSessionCoordinator
        self.attentionCenter = attentionCenter
        self.integrationStatus = integrationStatus
        self.now = now
        self.launchWindow = launchWindow
    }

    private func refresh(_ tracker: inout AgentJobTracker) {
        let controller = windowSessionCoordinator.controller(
            owning: tracker.paneID
        )
        let candidateRuns = controller == nil
            ? []
            : attentionCenter.runs(
                forPane: tracker.paneID,
                provider: tracker.provider.agentProvider
            )
        tracker.reconcile(
            runs: candidateRuns,
            paneExists: controller != nil,
            now: now()
        )
    }

    private func isValidLabel(_ label: String?) -> Bool {
        guard let label else { return true }
        return label.unicodeScalars.count <= Self.maximumLabelScalars
            && label.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    /// A model id is a single shell token dropped straight into the launch
    /// command (see `AgentLaunchPlan.modelSegment`), so — unlike a label,
    /// which only travels as a quoted argument — it must be nonempty and
    /// contain no whitespace, on top of the same length/control-character
    /// checks `isValidLabel` applies.
    private func isValidModel(_ model: String?) -> Bool {
        guard let model else { return true }
        return !model.isEmpty
            && model.unicodeScalars.count <= Self.maximumLabelScalars
            && model.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
                    && !CharacterSet.whitespacesAndNewlines.contains($0)
            }
    }

    /// `--access inherit` support: reads the anchor pane's own foreground
    /// process (the lead agent that's asking to spawn a worker) and, if
    /// it's the same provider as the requested worker, extracts its mode
    /// flags to carry onto the worker. Returns `.success(nil-or-flags)` on
    /// a resolvable lead, `.failure("inherit-unavailable")` when the
    /// anchor pane's foreground process can't be read at all or is a
    /// different provider than `requestedProvider` -- inheriting another
    /// provider's flags onto this worker would be meaningless (they don't
    /// share a flag vocabulary) and silently ignoring the mismatch would
    /// launch the worker in a mode the caller never asked for.
    private func resolveInheritedMode(
        controller: TerminalWindowController,
        anchorSurfaceID: TerminalSurfaceID,
        requestedProvider: AgentWorkerProvider
    ) -> Result<[String]?, AgentControlFailure> {
        guard let invocation = controller.foregroundProcessInvocation(
            forPane: anchorSurfaceID
        ) else {
            return .failure(AgentControlFailure("inherit-unavailable"))
        }
        guard let leadProvider = TerminalAgentProcessDetector.provider(
            executablePath: invocation.executablePath,
            arguments: invocation.arguments
        ), leadProvider == requestedProvider.agentProvider else {
            return .failure(AgentControlFailure("inherit-unavailable"))
        }
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: requestedProvider,
            leadArguments: invocation.arguments
        )
        return .success(arguments)
    }
}

extension AgentJobCoordinator: ControlServerAgentDelegate {
    func controlServer(
        _ server: ControlServer,
        spawnAgentAnchorPaneID anchorPaneID: String,
        direction: ControlSplitDirection,
        provider: AgentWorkerProvider,
        cwd: String?,
        access: AgentAccessPolicy,
        model: String?,
        task: String,
        label: String?
    ) -> Result<AgentJobSnapshot, AgentControlFailure> {
        guard let anchorSurfaceID = TerminalSurfaceID(
            uuidString: anchorPaneID
        ),
            let controller = windowSessionCoordinator.controller(
                owning: anchorSurfaceID
            )
        else {
            return .failure(AgentControlFailure("pane-not-found"))
        }

        guard !task.isEmpty else {
            return .failure(AgentControlFailure("invalid-task"))
        }
        guard isValidLabel(label) else {
            return .failure(AgentControlFailure("invalid-label"))
        }
        guard isValidModel(model) else {
            return .failure(AgentControlFailure("invalid-model"))
        }

        let status = integrationStatus(provider.agentProvider)
        if let failureCode = AgentIntegrationPreflight.failureCode(
            for: status
        ) {
            return .failure(AgentControlFailure(failureCode))
        }

        let resolvedWorkingDirectory: URL
        if let cwd {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: cwd,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                return .failure(AgentControlFailure("invalid-cwd"))
            }
            resolvedWorkingDirectory = URL(
                fileURLWithPath: cwd,
                isDirectory: true
            )
        } else {
            resolvedWorkingDirectory = controller.workingDirectory(
                forPane: anchorSurfaceID
            ) ?? controller.currentWorkingDirectory
        }

        var resolvedAccess = access
        var inheritedModeArguments: [String]?
        if access == .inherit {
            switch resolveInheritedMode(
                controller: controller,
                anchorSurfaceID: anchorSurfaceID,
                requestedProvider: provider
            ) {
            case let .failure(failure):
                return .failure(failure)
            case let .success(arguments):
                if let arguments, !arguments.isEmpty {
                    inheritedModeArguments = arguments
                } else {
                    // The lead is running in its default mode -- nothing
                    // to inherit, so fall back to the normal
                    // access-derived flags exactly as if `--access
                    // workspace-write` had been requested.
                    resolvedAccess = .workspaceWrite
                }
            }
        }

        let splitDirection = SplitDirection(rawValue: direction.rawValue)
            ?? .right
        let initialInput = AgentLaunchPlan.initialInput(
            provider: provider,
            access: resolvedAccess,
            model: model,
            inheritedModeArguments: inheritedModeArguments,
            task: task
        )

        guard let newPaneID = controller.splitPane(
            anchorSurfaceID,
            direction: splitDirection,
            workingDirectory: resolvedWorkingDirectory,
            initialInput: initialInput,
            orchestrated: true
        ) else {
            return .failure(AgentControlFailure("spawn-failed"))
        }

        // Captured immediately after the pane exists, before the worker
        // process has had any chance to report a run — see
        // `AgentJobTracker`'s documentation on why this baseline still
        // matters even though it's normally empty for a brand-new pane.
        let baselineRuns = attentionCenter.runs(
            forPane: newPaneID,
            provider: provider.agentProvider
        )
        let tracker = AgentJobTracker(
            paneID: newPaneID,
            provider: provider,
            label: label,
            baselineRunIDs: Set(baselineRuns.map(\.id)),
            createdAt: now(),
            launchWindow: launchWindow
        )
        trackers[tracker.jobID] = tracker
        return .success(tracker.snapshot)
    }

    func controlServer(
        _ server: ControlServer,
        refreshedAgentJobSnapshotForJobID jobID: AgentJobID
    ) -> Result<AgentJobSnapshot, AgentControlFailure> {
        guard var tracker = trackers[jobID] else {
            return .failure(AgentControlFailure("job-not-found"))
        }
        refresh(&tracker)
        trackers[jobID] = tracker
        return .success(tracker.snapshot)
    }

    func controlServer(
        _ server: ControlServer,
        agentResultContentForJobID jobID: AgentJobID
    ) -> Result<(AgentJobSnapshot, ControlPaneContent), AgentControlFailure> {
        guard var tracker = trackers[jobID] else {
            return .failure(AgentControlFailure("job-not-found"))
        }
        refresh(&tracker)
        trackers[jobID] = tracker

        let paneIDString = tracker.paneID.rawValue.uuidString
        guard let controller = windowSessionCoordinator.controller(
            owning: tracker.paneID
        ),
            let remoteContent = controller.remotePaneContent(
                forPane: tracker.paneID
            )
        else {
            // The pane is gone — `refresh` above already moved a
            // nonterminal job to `.lost`. Still answer with the job's
            // snapshot rather than failing the whole request; there's
            // simply no screen text left to show.
            return .success((
                tracker.snapshot,
                ControlPaneContent(
                    paneID: paneIDString,
                    text: "",
                    cursorRow: nil,
                    cursorColumn: nil
                )
            ))
        }
        return .success((
            tracker.snapshot,
            ControlPaneContent(
                paneID: paneIDString,
                text: remoteContent.text,
                cursorRow: remoteContent.cursorRow,
                cursorColumn: remoteContent.cursorColumn
            )
        ))
    }

    func controlServer(
        _ server: ControlServer,
        sendAgentText text: String,
        pressEnter: Bool,
        toJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        guard var tracker = trackers[jobID] else {
            return .failure(AgentControlFailure("job-not-found"))
        }
        refresh(&tracker)
        guard let controller = windowSessionCoordinator.controller(
            owning: tracker.paneID
        ) else {
            trackers[jobID] = tracker
            return .failure(AgentControlFailure("job-lost"))
        }
        // A follow-up `agent send` into a job whose previously bound run
        // already finished must rebind before delivering the input, or
        // the eventual `agent wait --until completed` would resolve
        // immediately against the stale, already-terminal run instead of
        // the new one this follow-up produces. No-op if the job is still
        // tracking an active run — see AgentJobTracker.prepareForFollowUp.
        tracker.prepareForFollowUp(
            knownRunIDs: Set(
                attentionCenter.runs(
                    forPane: tracker.paneID,
                    provider: tracker.provider.agentProvider
                ).map(\.id)
            ),
            now: now(),
            launchWindow: launchWindow
        )
        guard controller.deliverRemoteInput(
            paneID: tracker.paneID,
            text: text,
            pressEnter: pressEnter
        ) else {
            trackers[jobID] = tracker
            return .failure(AgentControlFailure("job-lost"))
        }
        trackers[jobID] = tracker
        return .success(())
    }

    func controlServer(
        _ server: ControlServer,
        focusAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        guard var tracker = trackers[jobID] else {
            return .failure(AgentControlFailure("job-not-found"))
        }
        refresh(&tracker)
        trackers[jobID] = tracker
        guard let controller = windowSessionCoordinator.controller(
            owning: tracker.paneID
        ), controller.focus(pane: tracker.paneID) else {
            return .failure(AgentControlFailure("job-lost"))
        }
        return .success(())
    }

    func controlServer(
        _ server: ControlServer,
        closeAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        guard var tracker = trackers[jobID] else {
            return .failure(AgentControlFailure("job-not-found"))
        }
        if let controller = windowSessionCoordinator.controller(
            owning: tracker.paneID
        ) {
            _ = controller.closePane(forControl: tracker.paneID)
        }
        // The pane is gone (or never existed) either way now; mark a
        // nonterminal job `.lost` per the documented `close` contract
        // instead of leaving it `.launching`/`.running` forever.
        tracker.reconcile(runs: [], paneExists: false, now: now())
        trackers[jobID] = tracker
        return .success(())
    }
}
