import Foundation
import MyTTYCore

/// Per-surface cache in front of `TerminalAgentProcessDetector.provider(processID:)`,
/// so the 0.5s poll in `AgentStatusPollingCoordinator` only pays for the
/// expensive `KERN_PROCARGS2` argv copy and string classification when the
/// foreground process could actually be different from the last tick.
///
/// Cache key: `(pid, process start time, executable path)`.
/// - Start time (`proc_pidinfo(PROC_PIDTBSDINFO)`) defeats pid reuse — a
///   new process recycling an old pid has a different start time.
/// - Executable path (`proc_pidpath`) defeats an in-place `exec` to a
///   different binary under the same pid and start time.
/// Both are cheap per-tick probes (a couple of syscalls into small
/// stack/fixed buffers); the argv copy and classification only run on a
/// key miss.
///
/// Known residual staleness, accepted: `exec` from one script to another
/// under the *same* interpreter binary (same pid + start time + path,
/// different argv) isn't detected — the cached classification sticks until
/// the pid, start time, or executable path actually changes.
///
/// Negative results (`nil`, the steady state for a plain shell) are cached
/// too, so a stable non-agent foreground process costs only the two probes
/// per tick, never a re-scan of its argv.
@MainActor
final class AgentProcessProviderCache {
    private struct ProcessKey: Equatable {
        let pid: pid_t
        let startTimeSeconds: UInt64
        let startTimeMicroseconds: UInt64
        let executablePath: String
    }

    private var entries: [TerminalSurfaceID: (key: ProcessKey, provider: AgentProvider?)] = [:]

    private let startTime: (pid_t) -> (seconds: UInt64, microseconds: UInt64)?
    private let executablePath: (pid_t) -> String?
    private let classify: (pid_t) -> AgentProvider?

    init(
        startTime: @escaping (pid_t) -> (seconds: UInt64, microseconds: UInt64)? =
            TerminalAgentProcessDetector.startTime(processID:),
        executablePath: @escaping (pid_t) -> String? =
            TerminalAgentProcessDetector.executablePath(processID:),
        classify: @escaping (pid_t) -> AgentProvider? =
            TerminalAgentProcessDetector.provider(processID:)
    ) {
        self.startTime = startTime
        self.executablePath = executablePath
        self.classify = classify
    }

    /// Drops cache entries for surfaces that no longer exist. Call once
    /// per poll tick, mirroring `AgentSessionThrottleCache.purge`.
    func purge(activeSurfaceIDs: some Sequence<TerminalSurfaceID>) {
        let active = Set(activeSurfaceIDs)
        entries = entries.filter { active.contains($0.key) }
    }

    /// The provider (if any) running in `processID`'s foreground, using the
    /// cached classification when the process identity is unchanged since
    /// the last call for `surfaceID`.
    func provider(
        surfaceID: TerminalSurfaceID,
        processID: pid_t
    ) -> AgentProvider? {
        guard processID > 0 else { return nil }

        guard let startTime = startTime(processID),
              let executablePath = executablePath(processID)
        else {
            // A transient probe failure must not pin a stale or negative
            // result — fall through to full classification, uncached.
            return classify(processID)
        }

        let key = ProcessKey(
            pid: processID,
            startTimeSeconds: startTime.seconds,
            startTimeMicroseconds: startTime.microseconds,
            executablePath: executablePath
        )
        if let cached = entries[surfaceID], cached.key == key {
            return cached.provider
        }

        let provider = classify(processID)
        entries[surfaceID] = (key: key, provider: provider)
        return provider
    }
}
