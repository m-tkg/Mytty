import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// Characterization tests for `AgentSessionThrottleCache`: they pin down
/// the throttling behavior that used to live inline in
/// `TerminalWindowController` (fingerprint-based skipping for Claude Code,
/// a 5s timed cache for the other providers) so the extraction in
/// AgentProviderRuntime.swift didn't change it. A `Box<Date>` stands in for
/// the injected clock so tests can move time forward deterministically
/// instead of racing the wall clock.
@Suite("Agent session throttle cache")
struct AgentSessionThrottleCacheTests {
    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    @MainActor
    private func makeCache(startingAt date: Date) -> (AgentSessionThrottleCache, Box<Date>) {
        let clock = Box(date)
        let cache = AgentSessionThrottleCache(now: { clock.value })
        return (cache, clock)
    }

    @Test("reuses the timed result within the lifetime window")
    @MainActor
    func timedStatusReusesWithinWindow() {
        let (cache, clock) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceID = TerminalSurfaceID()
        var fetchCount = 0
        let status = AgentSessionStatus(
            sessionID: "session-1",
            modelName: "model-a",
            contextRemainingPercent: 50
        )

        func fetch() -> AgentSessionStatus? {
            fetchCount += 1
            return status
        }

        let first = cache.timedStatus(
            surfaceID: surfaceID,
            sessionID: "session-1",
            fetch: fetch
        )
        clock.value.addTimeInterval(4.9)
        let second = cache.timedStatus(
            surfaceID: surfaceID,
            sessionID: "session-1",
            fetch: fetch
        )

        #expect(first == status)
        #expect(second == status)
        #expect(fetchCount == 1)
    }

    @Test("refetches once the lifetime window elapses")
    @MainActor
    func timedStatusExpiresAfterLifetime() {
        let (cache, clock) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceID = TerminalSurfaceID()
        var fetchCount = 0

        func fetch() -> AgentSessionStatus? {
            fetchCount += 1
            return AgentSessionStatus(
                sessionID: "session-1",
                modelName: "model-\(fetchCount)",
                contextRemainingPercent: nil
            )
        }

        let first = cache.timedStatus(
            surfaceID: surfaceID,
            sessionID: "session-1",
            fetch: fetch
        )
        clock.value.addTimeInterval(5)
        let second = cache.timedStatus(
            surfaceID: surfaceID,
            sessionID: "session-1",
            fetch: fetch
        )

        #expect(fetchCount == 2)
        #expect(first?.modelName == "model-1")
        #expect(second?.modelName == "model-2")
    }

    @Test("refetches immediately when the hook-reported session ID changes")
    @MainActor
    func timedStatusInvalidatesOnSessionIDChange() {
        let (cache, clock) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceID = TerminalSurfaceID()
        var fetchCount = 0

        func fetch() -> AgentSessionStatus? {
            fetchCount += 1
            return AgentSessionStatus(
                sessionID: "irrelevant",
                modelName: "model-\(fetchCount)",
                contextRemainingPercent: nil
            )
        }

        _ = cache.timedStatus(
            surfaceID: surfaceID,
            sessionID: "session-1",
            fetch: fetch
        )
        clock.value.addTimeInterval(0.1)
        let afterChange = cache.timedStatus(
            surfaceID: surfaceID,
            sessionID: "session-2",
            fetch: fetch
        )

        #expect(fetchCount == 2)
        #expect(afterChange?.modelName == "model-2")
    }

    @Test("keeps timed caches independent per surface")
    @MainActor
    func timedStatusIsolatesSurfaces() {
        let (cache, _) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceA = TerminalSurfaceID()
        let surfaceB = TerminalSurfaceID()
        var fetchCount = 0

        func fetch() -> AgentSessionStatus? {
            fetchCount += 1
            return nil
        }

        _ = cache.timedStatus(surfaceID: surfaceA, sessionID: "s", fetch: fetch)
        _ = cache.timedStatus(surfaceID: surfaceB, sessionID: "s", fetch: fetch)

        #expect(fetchCount == 2)
    }

    @Test("skips recomputing the Claude Code status while the transcript fingerprint is unchanged")
    @MainActor
    func claudeCodeStatusSkipsUnchangedFingerprint() {
        let (cache, _) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceID = TerminalSurfaceID()
        let transcript = URL(fileURLWithPath: "/tmp/transcript.jsonl")
        let fingerprint = (mtime: Date(timeIntervalSince1970: 500), size: UInt64(10))
        var computeCount = 0

        func compute() -> ClaudeCodeTranscriptSnapshot {
            computeCount += 1
            return ClaudeCodeTranscriptSnapshot(
                status: AgentSessionStatus(
                    sessionID: "claude-session",
                    modelName: "claude-fable-5",
                    contextRemainingPercent: 80
                ),
                interruption: nil
            )
        }

        let first = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: transcript,
            fingerprint: fingerprint,
            compute: compute
        )
        let second = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: transcript,
            fingerprint: fingerprint,
            compute: compute
        )

        #expect(first == second)
        #expect(computeCount == 1)
    }

    @Test("recomputes the Claude Code status once the transcript fingerprint changes")
    @MainActor
    func claudeCodeStatusRecomputesOnChangedFingerprint() {
        let (cache, _) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceID = TerminalSurfaceID()
        let transcript = URL(fileURLWithPath: "/tmp/transcript.jsonl")
        var computeCount = 0

        func compute() -> ClaudeCodeTranscriptSnapshot {
            computeCount += 1
            return ClaudeCodeTranscriptSnapshot(
                status: AgentSessionStatus(
                    sessionID: "claude-session",
                    modelName: "claude-fable-\(computeCount)",
                    contextRemainingPercent: nil
                ),
                interruption: nil
            )
        }

        _ = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: transcript,
            fingerprint: (mtime: Date(timeIntervalSince1970: 500), size: 10),
            compute: compute
        )
        let afterSizeChange = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: transcript,
            fingerprint: (mtime: Date(timeIntervalSince1970: 500), size: 20),
            compute: compute
        )
        let afterMtimeChange = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: transcript,
            fingerprint: (mtime: Date(timeIntervalSince1970: 600), size: 20),
            compute: compute
        )

        #expect(computeCount == 3)
        #expect(afterSizeChange.status?.modelName == "claude-fable-2")
        #expect(afterMtimeChange.status?.modelName == "claude-fable-3")
    }

    @Test("recomputes the Claude Code status once a different transcript URL is tracked")
    @MainActor
    func claudeCodeStatusRecomputesOnChangedTranscriptURL() {
        let (cache, _) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceID = TerminalSurfaceID()
        let fingerprint = (mtime: Date(timeIntervalSince1970: 500), size: UInt64(10))
        var computeCount = 0

        func compute() -> ClaudeCodeTranscriptSnapshot {
            computeCount += 1
            return ClaudeCodeTranscriptSnapshot(
                status: nil,
                interruption: nil
            )
        }

        _ = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: URL(fileURLWithPath: "/tmp/a.jsonl"),
            fingerprint: fingerprint,
            compute: compute
        )
        _ = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: URL(fileURLWithPath: "/tmp/b.jsonl"),
            fingerprint: fingerprint,
            compute: compute
        )

        #expect(computeCount == 2)
    }

    @Test("clearing the Claude Code fingerprint forces a recompute")
    @MainActor
    func clearClaudeCodeFingerprintForcesRecompute() {
        let (cache, _) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let surfaceID = TerminalSurfaceID()
        let transcript = URL(fileURLWithPath: "/tmp/transcript.jsonl")
        let fingerprint = (mtime: Date(timeIntervalSince1970: 500), size: UInt64(10))
        var computeCount = 0

        func compute() -> ClaudeCodeTranscriptSnapshot {
            computeCount += 1
            return ClaudeCodeTranscriptSnapshot(
                status: nil,
                interruption: nil
            )
        }

        _ = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: transcript,
            fingerprint: fingerprint,
            compute: compute
        )
        cache.clearClaudeCodeFingerprint(surfaceID: surfaceID)
        _ = cache.claudeCodeSnapshot(
            surfaceID: surfaceID,
            transcript: transcript,
            fingerprint: fingerprint,
            compute: compute
        )

        #expect(computeCount == 2)
    }

    @Test("purging drops both caches for surfaces that are no longer active")
    @MainActor
    func purgeDropsInactiveSurfaces() {
        let (cache, clock) = makeCache(startingAt: Date(timeIntervalSince1970: 1_000))
        let keptSurface = TerminalSurfaceID()
        let droppedSurface = TerminalSurfaceID()
        let transcript = URL(fileURLWithPath: "/tmp/transcript.jsonl")
        let fingerprint = (mtime: Date(timeIntervalSince1970: 500), size: UInt64(10))

        _ = cache.claudeCodeSnapshot(
            surfaceID: droppedSurface,
            transcript: transcript,
            fingerprint: fingerprint,
            compute: {
                ClaudeCodeTranscriptSnapshot(
                    status: nil,
                    interruption: nil
                )
            }
        )
        _ = cache.timedStatus(
            surfaceID: droppedSurface,
            sessionID: "s",
            fetch: { nil }
        )
        _ = cache.timedStatus(
            surfaceID: keptSurface,
            sessionID: "s",
            fetch: { nil }
        )

        cache.purge(activeSurfaceIDs: [keptSurface])

        var claudeComputeCount = 0
        _ = cache.claudeCodeSnapshot(
            surfaceID: droppedSurface,
            transcript: transcript,
            fingerprint: fingerprint,
            compute: {
                claudeComputeCount += 1
                return ClaudeCodeTranscriptSnapshot(
                    status: nil,
                    interruption: nil
                )
            }
        )
        #expect(claudeComputeCount == 1)

        var timedFetchCountForKept = 0
        clock.value.addTimeInterval(1)
        _ = cache.timedStatus(
            surfaceID: keptSurface,
            sessionID: "s",
            fetch: {
                timedFetchCountForKept += 1
                return nil
            }
        )
        // Not purged (still active) and within the 5s window, so no refetch.
        #expect(timedFetchCountForKept == 0)

        var timedFetchCountForDropped = 0
        _ = cache.timedStatus(
            surfaceID: droppedSurface,
            sessionID: "s",
            fetch: {
                timedFetchCountForDropped += 1
                return nil
            }
        )
        // Purged, so the entry is gone even though it's still within the
        // 5s window and the session ID didn't change.
        #expect(timedFetchCountForDropped == 1)
    }
}
