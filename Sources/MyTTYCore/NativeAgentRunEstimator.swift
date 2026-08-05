import Foundation

/// Estimates an agent run's start/finish for panes whose provider hook
/// integration isn't installed. Without hooks, Mytty has no `started` /
/// `succeeded` / `failed` events for that pane at all -- the status bar,
/// Attention Inbox, `mytty-ctl wait`, and job binding all go dark for a
/// provider the user hasn't (or can't) wire up hooks for. This tracker
/// turns two signals `AgentStatusPollingCoordinator` and OSC 133 already
/// observe -- a known agent executable appearing/disappearing in a pane's
/// foreground process, and the shell reporting a foreground command ended
/// -- into the same `AgentEvent` shape hooks produce, so nothing downstream
/// needs to know the difference.
///
/// One "epoch" is tracked per surface at a time: the span from a detected
/// agent process appearing in that pane's foreground to it finishing or
/// disappearing. `epochKey` -- derived from the surface, provider, pid, and
/// a per-(surface, pid) occurrence counter -- is the sole source of the
/// deterministic run/event IDs `AgentHookEventAdapter`'s `native*` factories
/// mint, so the same observed sequence always reproduces the same IDs (safe
/// to replay) while pid reuse across two unrelated launches on the same
/// pane still yields two distinct runs.
///
/// Pure state machine, no timer or `Date()` of its own -- see
/// `NativeAgentRunCoordinator` in `MyTTYApp`, which pairs this with an
/// actual `Timer` the same way `CursorApprovalCoordinator` pairs
/// `CursorApprovalPendingTracker`.
public final class NativeAgentRunEstimator {
    private enum Phase: Equatable {
        case pendingStart(deadline: Date)
        case started
        case ended
    }

    private struct Epoch {
        let provider: AgentProvider
        let pid: pid_t
        let epochKey: String
        var phase: Phase
        /// Set once a real (non-`mytty.`) hook event lands for this
        /// surface+provider: the provider's own hooks are covering this
        /// run now, so this estimator must never emit for it again, but the
        /// epoch stays registered (rather than being removed outright) so a
        /// later `providerChanged`/`commandFinished` call for the same
        /// still-foreground process has something to silently clear.
        var hookCovered: Bool
    }

    private struct OccurrenceKey: Hashable {
        let surfaceID: TerminalSurfaceID
        let pid: pid_t
    }

    private let startGrace: TimeInterval
    private var epochs: [TerminalSurfaceID: Epoch] = [:]
    private var occurrenceCounters: [OccurrenceKey: Int] = [:]

    /// - Parameter startGrace: How long a detected agent process must stay
    ///   in the foreground before this estimator commits to a `started`
    ///   event. Filters out processes that appear and vanish too quickly to
    ///   be a real agent run (e.g. a version check the agent shells out to
    ///   on launch that briefly shares its process name).
    public init(startGrace: TimeInterval = 3) {
        self.startGrace = startGrace
    }

    /// The soonest `pendingStart` deadline still outstanding, or `nil` if
    /// nothing is waiting. Mirrors `CursorApprovalPendingTracker.nextDeadline`
    /// -- the caller (re)arms its single timer for this value after every
    /// call that can change it.
    public var nextDeadline: Date? {
        epochs.values.compactMap { epoch -> Date? in
            guard case let .pendingStart(deadline) = epoch.phase,
                  !epoch.hookCovered
            else { return nil }
            return deadline
        }.min()
    }

    /// Feed every foreground-provider change `AgentStatusPollingCoordinator`
    /// reports for a surface here, including a change to `nil` when the
    /// polled foreground process is no longer a known agent (or the surface
    /// itself is gone). `suppressedProviders` -- providers whose hook
    /// integration is already installed -- decides whether the *new*
    /// provider gets tracked at all; the hook side owns those runs and this
    /// estimator must stay out of the way entirely, never emitting even a
    /// `started`.
    @discardableResult
    public func providerChanged(
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider?,
        processID: pid_t?,
        suppressedProviders: Set<AgentProvider>,
        now: Date
    ) -> [AgentEvent] {
        var events: [AgentEvent] = []

        if let existing = epochs[surfaceID] {
            guard existing.provider != provider || existing.pid != processID
            else {
                // Not actually a transition -- nothing to end or start.
                return events
            }
            if case .started = existing.phase, !existing.hookCovered {
                events.append(
                    AgentHookEventAdapter.nativeProcessExitedEvent(
                        provider: existing.provider,
                        surfaceID: surfaceID,
                        epochKey: existing.epochKey,
                        occurredAt: now
                    )
                )
            }
            epochs[surfaceID] = nil
        }

        guard let provider, let processID else { return events }
        guard !suppressedProviders.contains(provider) else { return events }

        let occurrenceKey = OccurrenceKey(surfaceID: surfaceID, pid: processID)
        let occurrence = occurrenceCounters[occurrenceKey, default: 0]
        occurrenceCounters[occurrenceKey] = occurrence + 1

        epochs[surfaceID] = Epoch(
            provider: provider,
            pid: processID,
            epochKey: Self.epochKey(
                surfaceID: surfaceID,
                provider: provider,
                pid: processID,
                occurrence: occurrence
            ),
            phase: .pendingStart(deadline: now.addingTimeInterval(startGrace)),
            hookCovered: false
        )
        return events
    }

    /// Feed OSC 133's command-end report here for the surface it belongs
    /// to. Only a `started` epoch produces a terminal event; a
    /// `pendingStart` epoch means the agent process exited before the
    /// start grace elapsed, too short-lived to have ever been announced, so
    /// it's dropped without ever emitting a `started` for it.
    @discardableResult
    public func commandFinished(
        surfaceID: TerminalSurfaceID,
        exitCode: Int?,
        now: Date
    ) -> [AgentEvent] {
        guard let epoch = epochs[surfaceID] else { return [] }

        switch epoch.phase {
        case .pendingStart:
            epochs[surfaceID] = nil
            return []

        case .started:
            guard !epoch.hookCovered else {
                epochs[surfaceID] = nil
                return []
            }
            var updated = epoch
            updated.phase = .ended
            epochs[surfaceID] = updated
            return [
                AgentHookEventAdapter.nativeCommandFinishedEvent(
                    provider: epoch.provider,
                    surfaceID: surfaceID,
                    epochKey: epoch.epochKey,
                    exitCode: exitCode,
                    occurredAt: now
                )
            ]

        case .ended:
            // Already ended by a prior commandFinished; the disappearance
            // that will follow on the next poll tick must not double-end.
            return []
        }
    }

    /// Feed every `AgentEvent` observed for a surface here, including ones
    /// this estimator itself produced -- `AgentHookEventAdapter
    /// .isMyttySynthesizedHookName` filters those out, the same guard
    /// `CursorApprovalPendingTracker` relies on for its own synthetic
    /// event. A real hook delivery for the surface+provider this estimator
    /// is tracking means the provider's own hooks are now covering that
    /// run, so this estimator must defer to them for the rest of the run's
    /// lifecycle rather than racing a second, conflicting end event.
    public func observeRealEvent(_ event: AgentEvent) {
        guard !AgentHookEventAdapter.isMyttySynthesizedHookName(event.hookName)
        else { return }
        guard var epoch = epochs[event.surfaceID],
              epoch.provider == event.provider
        else { return }
        epoch.hookCovered = true
        epochs[event.surfaceID] = epoch
    }

    /// Transitions every `pendingStart` epoch whose deadline has passed to
    /// `started`, emitting the started event for each. The real timer calls
    /// this at each deadline; tests call it directly to stay independent of
    /// wall-clock time.
    public func fireDue(now: Date) -> [AgentEvent] {
        var events: [AgentEvent] = []
        for (surfaceID, epoch) in epochs {
            guard case let .pendingStart(deadline) = epoch.phase,
                  deadline <= now
            else { continue }

            guard !epoch.hookCovered else {
                epochs[surfaceID] = nil
                continue
            }

            var updated = epoch
            updated.phase = .started
            epochs[surfaceID] = updated
            events.append(
                AgentHookEventAdapter.nativeStartedEvent(
                    provider: epoch.provider,
                    surfaceID: surfaceID,
                    epochKey: epoch.epochKey,
                    occurredAt: now
                )
            )
        }
        return events
    }

    private static func epochKey(
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider,
        pid: pid_t,
        occurrence: Int
    ) -> String {
        "\(surfaceID.rawValue.uuidString)\u{0}\(provider.rawValue)\u{0}\(pid)\u{0}\(occurrence)"
    }
}
