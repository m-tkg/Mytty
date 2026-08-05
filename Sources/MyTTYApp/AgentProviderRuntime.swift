import Foundation
import GhosttyAdapter
import MyTTYCore

/// Everything an `AgentProviderRuntime` needs to compute a pane's session
/// status. `hookSessionID`/`workingDirectory` are closures (not stored
/// values) so a runtime that doesn't need them — Codex reads its session
/// straight off the foreground process — never pays for the lookup.
@MainActor
struct AgentSessionQueryContext {
    let surfaceID: TerminalSurfaceID
    let surface: GhosttySurfaceView
    let hookSessionID: () -> String?
    let workingDirectory: () -> URL?
}

/// Per-surface throttling for session-status lookups, shared by every
/// `AgentProviderRuntime`. Two strategies are in use:
///
/// - `claudeCodeSnapshot`: skip re-parsing the Claude Code transcript unless
///   its (mtime, size) fingerprint changed since the last poll.
/// - `claudeCodeModelSelection`: reuse the resolved model selection for up
///   to `lifetime` seconds, since resolving it reads settings files.
/// - `timedStatus`: reuse the last result for up to `lifetime` seconds
///   unless the hook-reported session ID changed — used by providers whose
///   local data source (SQLite database or settings file) is too costly to
///   re-read on every 0.5s poll tick.
///
/// `now` is injectable so tests can drive the 5s window deterministically;
/// production call sites rely on the `Date.init` default.
@MainActor
final class AgentSessionThrottleCache {
    private let now: () -> Date
    private var claudeTranscriptFingerprints: [
        TerminalSurfaceID: (
            url: URL,
            mtime: Date,
            size: UInt64,
            selection: String?,
            snapshot: ClaudeCodeTranscriptSnapshot
        )
    ] = [:]
    private var claudeModelSelections: [
        TerminalSurfaceID: (fetchedAt: Date, selection: String?)
    ] = [:]
    private var timedCache: [
        TerminalSurfaceID: (
            sessionID: String?, fetchedAt: Date, status: AgentSessionStatus?
        )
    ] = [:]

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Drops cache entries for surfaces that no longer exist. Must be
    /// called once per poll tick before computing fresh statuses — mirrors
    /// how the cache used to be filtered inline in
    /// `TerminalWindowController.refreshAgentSessionIDs`.
    func purge(activeSurfaceIDs: some Sequence<TerminalSurfaceID>) {
        let active = Set(activeSurfaceIDs)
        claudeTranscriptFingerprints = claudeTranscriptFingerprints.filter {
            active.contains($0.key)
        }
        claudeModelSelections = claudeModelSelections.filter {
            active.contains($0.key)
        }
        timedCache = timedCache.filter { active.contains($0.key) }
    }

    func clearClaudeCodeFingerprint(surfaceID: TerminalSurfaceID) {
        claudeTranscriptFingerprints[surfaceID] = nil
    }

    /// `selection` takes part in the cache key: it decides the context
    /// window the snapshot's percentage was measured against, so switching
    /// models must re-parse even when the transcript hasn't changed yet.
    func claudeCodeSnapshot(
        surfaceID: TerminalSurfaceID,
        transcript: URL,
        fingerprint: (mtime: Date, size: UInt64),
        selection: String?,
        compute: () -> ClaudeCodeTranscriptSnapshot
    ) -> ClaudeCodeTranscriptSnapshot {
        if let cached = claudeTranscriptFingerprints[surfaceID],
           cached.url == transcript,
           cached.mtime == fingerprint.mtime,
           cached.size == fingerprint.size,
           cached.selection == selection {
            return cached.snapshot
        }

        let snapshot = compute()
        claudeTranscriptFingerprints[surfaceID] = (
            url: transcript,
            mtime: fingerprint.mtime,
            size: fingerprint.size,
            selection: selection,
            snapshot: snapshot
        )
        return snapshot
    }

    /// Resolving the selection reads up to three settings files, so it is
    /// kept out of the 0.5s tick the same way `timedStatus` keeps SQLite
    /// queries out of it.
    func claudeCodeModelSelection(
        surfaceID: TerminalSurfaceID,
        lifetime: TimeInterval = 5,
        resolve: () -> String?
    ) -> String? {
        let currentTime = now()
        if let cached = claudeModelSelections[surfaceID],
           currentTime.timeIntervalSince(cached.fetchedAt) < lifetime {
            return cached.selection
        }

        let selection = resolve()
        claudeModelSelections[surfaceID] = (
            fetchedAt: currentTime,
            selection: selection
        )
        return selection
    }

    func timedStatus(
        surfaceID: TerminalSurfaceID,
        sessionID: String?,
        lifetime: TimeInterval = 5,
        fetch: () -> AgentSessionStatus?
    ) -> AgentSessionStatus? {
        let currentTime = now()
        if let cached = timedCache[surfaceID],
           cached.sessionID == sessionID,
           currentTime.timeIntervalSince(cached.fetchedAt) < lifetime {
            return cached.status
        }

        let status = fetch()
        timedCache[surfaceID] = (
            sessionID: sessionID,
            fetchedAt: currentTime,
            status: status
        )
        return status
    }
}

/// A run the user interrupted, for providers that fire no hook on
/// interruption. `runKey` addresses the run the provider's hooks created;
/// `interruptionKey` addresses this particular interrupt, so a prompt that
/// is interrupted, continued, and interrupted again ends twice.
struct AgentRunInterruption: Equatable {
    let runKey: String
    let interruptionKey: String
}

/// What one poll tick learns about a pane from its provider's local data.
struct AgentProviderPollResult: Equatable {
    let status: AgentSessionStatus?
    let interruption: AgentRunInterruption?
    /// The current prompt-turn's lifecycle, when the provider's inspector
    /// derives one (Claude Code, Codex) -- feeds `NativeAgentRunEstimator
    /// .turnObserved` via `AgentStatusPollingCoordinator`. `nil` for every
    /// other provider, and for these two whenever the transcript tail
    /// carries no real prompt.
    let turn: AgentTurnObservation?

    init(
        status: AgentSessionStatus?,
        interruption: AgentRunInterruption? = nil,
        turn: AgentTurnObservation? = nil
    ) {
        self.status = status
        self.interruption = interruption
        self.turn = turn
    }
}

/// One implementation per agent provider: how to read its session state off
/// the pane, and which throttling strategy (if any) makes that cheap enough
/// to call on every 0.5s poll tick.
@MainActor
protocol AgentProviderRuntime {
    var provider: AgentProvider { get }

    func poll(
        context: AgentSessionQueryContext,
        throttle: AgentSessionThrottleCache
    ) -> AgentProviderPollResult
}

/// No throttling: `CodexSessionInspector` already scopes its search to the
/// surface's own foreground process, so there's nothing to fingerprint or
/// cache against.
struct CodexProviderRuntime: AgentProviderRuntime {
    let provider: AgentProvider = .codex

    func poll(
        context: AgentSessionQueryContext,
        throttle: AgentSessionThrottleCache
    ) -> AgentProviderPollResult {
        let snapshot = CodexSessionInspector.snapshot(
            processID: context.surface.foregroundProcessID
        )
        return AgentProviderPollResult(
            status: snapshot.status,
            turn: snapshot.turn
        )
    }
}

/// Fingerprint-throttled: the transcript is looked up on every tick (cheap
/// directory/file resolution) but only re-parsed when its (mtime, size)
/// changed.
struct ClaudeCodeProviderRuntime: AgentProviderRuntime {
    let provider: AgentProvider = .claudeCode

    /// Claude Code fires no hook when the user presses ESC, so an
    /// interrupted run would stay `running` forever; the transcript's
    /// interrupt marker — read in the same pass as the status — ends it.
    func poll(
        context: AgentSessionQueryContext,
        throttle: AgentSessionThrottleCache
    ) -> AgentProviderPollResult {
        let workingDirectory = context.workingDirectory()
        guard let transcript = ClaudeCodeSessionInspector.transcriptURL(
            sessionID: context.hookSessionID(),
            workingDirectory: workingDirectory
        ), let fingerprint = FileFingerprint.of(transcript) else {
            throttle.clearClaudeCodeFingerprint(surfaceID: context.surfaceID)
            return AgentProviderPollResult(status: nil)
        }

        // The transcript records the normalized model ID, so the context
        // window has to come from what the user selected instead.
        let selection = throttle.claudeCodeModelSelection(
            surfaceID: context.surfaceID
        ) {
            ClaudeCodeModelSelection.resolve(
                arguments: TerminalAgentProcessDetector.arguments(
                    processID: context.surface.foregroundProcessID
                ),
                workingDirectory: workingDirectory
            )
        }

        let snapshot = throttle.claudeCodeSnapshot(
            surfaceID: context.surfaceID,
            transcript: transcript,
            fingerprint: fingerprint,
            selection: selection
        ) {
            ClaudeCodeSessionInspector.snapshot(
                contentsOf: transcript,
                selection: selection
            )
        }
        return AgentProviderPollResult(
            status: snapshot.status,
            interruption: snapshot.interruption.map {
                AgentRunInterruption(
                    runKey: $0.promptID,
                    interruptionKey: $0.messageID
                )
            },
            turn: snapshot.turn
        )
    }
}

/// 5s-timed-cache providers: each reads a SQLite database or settings file
/// that's too costly to re-query on every 0.5s poll tick, so the last
/// result is reused for 5 seconds unless the hook-reported session ID
/// changed.
struct OpenCodeProviderRuntime: AgentProviderRuntime {
    let provider: AgentProvider = .openCode

    func poll(
        context: AgentSessionQueryContext,
        throttle: AgentSessionThrottleCache
    ) -> AgentProviderPollResult {
        let hookSessionID = context.hookSessionID()
        return AgentProviderPollResult(status: throttle.timedStatus(
            surfaceID: context.surfaceID,
            sessionID: hookSessionID
        ) {
            OpenCodeSessionInspector.status(sessionID: hookSessionID)
        })
    }
}

struct CursorProviderRuntime: AgentProviderRuntime {
    let provider: AgentProvider = .cursor

    func poll(
        context: AgentSessionQueryContext,
        throttle: AgentSessionThrottleCache
    ) -> AgentProviderPollResult {
        let hookSessionID = context.hookSessionID()
        return AgentProviderPollResult(status: throttle.timedStatus(
            surfaceID: context.surfaceID,
            sessionID: hookSessionID
        ) {
            CursorSessionInspector.status(
                sessionID: hookSessionID,
                workingDirectory: context.workingDirectory()
            )
        })
    }
}

struct AntigravityProviderRuntime: AgentProviderRuntime {
    let provider: AgentProvider = .antigravity

    func poll(
        context: AgentSessionQueryContext,
        throttle: AgentSessionThrottleCache
    ) -> AgentProviderPollResult {
        let hookSessionID = context.hookSessionID()
        return AgentProviderPollResult(status: throttle.timedStatus(
            surfaceID: context.surfaceID,
            sessionID: hookSessionID
        ) {
            AntigravitySessionInspector.status(sessionID: hookSessionID)
        })
    }
}

@MainActor
enum AgentProviderRuntimeRegistry {
    static let runtimes: [any AgentProviderRuntime] = [
        CodexProviderRuntime(),
        ClaudeCodeProviderRuntime(),
        OpenCodeProviderRuntime(),
        CursorProviderRuntime(),
        AntigravityProviderRuntime(),
    ]

    private static let byProvider: [AgentProvider: any AgentProviderRuntime] =
        Dictionary(uniqueKeysWithValues: runtimes.map { ($0.provider, $0) })

    static func runtime(for provider: AgentProvider) -> (any AgentProviderRuntime)? {
        byProvider[provider]
    }
}
