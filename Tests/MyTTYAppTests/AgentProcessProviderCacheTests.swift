import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// `AgentProcessProviderCache` is tested entirely through injected probe
/// closures — no real processes or machine-specific paths — so the cache
/// key logic (pid, start time, executable path) is exercised
/// deterministically regardless of what's actually running on the test
/// machine.
@Suite("Agent process provider cache")
@MainActor
struct AgentProcessProviderCacheTests {
    private typealias StartTime = (seconds: UInt64, microseconds: UInt64)

    private func makeCache(
        startTime: @escaping (pid_t) -> StartTime? = { _ in (1, 0) },
        executablePath: @escaping (pid_t) -> String? = { _ in "/usr/bin/env" },
        classifyDescendants: @escaping (pid_t)
            -> TerminalAgentProcessDetector.AgentProcess? = { _ in nil },
        classify: @escaping (pid_t) -> AgentProvider?
    ) -> AgentProcessProviderCache {
        AgentProcessProviderCache(
            startTime: startTime,
            executablePath: executablePath,
            classify: classify,
            classifyDescendants: classifyDescendants
        )
    }

    @Test("reuses the classification while the process identity is unchanged")
    func cacheHitSkipsReclassification() {
        var classifyCount = 0
        let cache = makeCache { _ in
            classifyCount += 1
            return .codex
        }
        let surfaceID = TerminalSurfaceID()

        let first = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider
        let second = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider

        #expect(first == .codex)
        #expect(second == .codex)
        #expect(classifyCount == 1)
    }

    @Test("reclassifies when the pid changes")
    func pidChangeReclassifies() {
        var classifyCount = 0
        let cache = makeCache { _ in
            classifyCount += 1
            return .codex
        }
        let surfaceID = TerminalSurfaceID()

        _ = cache.agentProcess(surfaceID: surfaceID, processID: 100)
        _ = cache.agentProcess(surfaceID: surfaceID, processID: 200)

        #expect(classifyCount == 2)
    }

    @Test("reclassifies when the start time changes under the same pid")
    func startTimeChangeReclassifies() {
        var classifyCount = 0
        var currentStartTime: StartTime = (1, 0)
        let cache = makeCache(
            startTime: { _ in currentStartTime },
            executablePath: { _ in "/usr/bin/env" },
            classify: { _ in
                classifyCount += 1
                return .codex
            }
        )
        let surfaceID = TerminalSurfaceID()

        _ = cache.agentProcess(surfaceID: surfaceID, processID: 100)
        currentStartTime = (2, 0)
        _ = cache.agentProcess(surfaceID: surfaceID, processID: 100)

        #expect(classifyCount == 2)
    }

    @Test("reclassifies when the executable path changes under the same pid and start time")
    func executablePathChangeReclassifies() {
        var classifyCount = 0
        var currentPath = "/usr/bin/env"
        let cache = makeCache(
            startTime: { _ in (1, 0) },
            executablePath: { _ in currentPath },
            classify: { _ in
                classifyCount += 1
                return .codex
            }
        )
        let surfaceID = TerminalSurfaceID()

        _ = cache.agentProcess(surfaceID: surfaceID, processID: 100)
        currentPath = "/usr/bin/codex"
        _ = cache.agentProcess(surfaceID: surfaceID, processID: 100)

        #expect(classifyCount == 2)
    }

    @Test("caches a negative result without re-invoking classify")
    func negativeResultIsCached() {
        var classifyCount = 0
        let cache = makeCache { _ in
            classifyCount += 1
            return nil
        }
        let surfaceID = TerminalSurfaceID()

        let first = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider
        let second = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider

        #expect(first == nil)
        #expect(second == nil)
        #expect(classifyCount == 1)
    }

    @Test("falls back to uncached classification when the start-time probe fails")
    func startTimeProbeFailureFallsBackUncached() {
        var classifyCount = 0
        let cache = makeCache(
            startTime: { _ in nil },
            executablePath: { _ in "/usr/bin/env" },
            classify: { _ in
                classifyCount += 1
                return .codex
            }
        )
        let surfaceID = TerminalSurfaceID()

        let first = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider
        let second = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider

        #expect(first == .codex)
        #expect(second == .codex)
        #expect(classifyCount == 2)
    }

    @Test("falls back to uncached classification when the executable-path probe fails")
    func executablePathProbeFailureFallsBackUncached() {
        var classifyCount = 0
        let cache = makeCache(
            startTime: { _ in (1, 0) },
            executablePath: { _ in nil },
            classify: { _ in
                classifyCount += 1
                return .codex
            }
        )
        let surfaceID = TerminalSurfaceID()

        let first = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider
        let second = cache.agentProcess(surfaceID: surfaceID, processID: 100)?.provider

        #expect(first == .codex)
        #expect(second == .codex)
        #expect(classifyCount == 2)
    }

    @Test("treats pid 0 and negative pids as no provider without touching the cache")
    func invalidPidIsNotCached() {
        var classifyCount = 0
        let cache = makeCache { _ in
            classifyCount += 1
            return .codex
        }
        let surfaceID = TerminalSurfaceID()

        #expect(cache.agentProcess(surfaceID: surfaceID, processID: 0) == nil)
        #expect(cache.agentProcess(surfaceID: surfaceID, processID: -1) == nil)
        #expect(classifyCount == 0)
    }

    @Test("purging drops cache entries for surfaces that are no longer active")
    func purgeDropsInactiveSurfaces() {
        var classifyCount = 0
        let cache = makeCache { _ in
            classifyCount += 1
            return .codex
        }
        let keptSurface = TerminalSurfaceID()
        let droppedSurface = TerminalSurfaceID()

        _ = cache.agentProcess(surfaceID: keptSurface, processID: 100)
        _ = cache.agentProcess(surfaceID: droppedSurface, processID: 100)
        #expect(classifyCount == 2)

        cache.purge(activeSurfaceIDs: [keptSurface])

        _ = cache.agentProcess(surfaceID: keptSurface, processID: 100)
        // Still cached (same key, surface kept): no re-classification.
        #expect(classifyCount == 2)

        _ = cache.agentProcess(surfaceID: droppedSurface, processID: 100)
        // Purged: same key, but the entry is gone.
        #expect(classifyCount == 3)
    }

    /// A wrapper script keeps the same pid, start time and executable path
    /// whether or not it currently has an agent under it, so the descendant
    /// scan must not ride on the cached negative.
    @Test("re-runs the descendant scan on every call while nothing is in front")
    func descendantScanIsNotCached() {
        var classifyCount = 0
        var descendantCount = 0
        var descendant: TerminalAgentProcessDetector.AgentProcess?
        let cache = makeCache(
            classifyDescendants: { _ in
                descendantCount += 1
                return descendant
            },
            classify: { _ in
                classifyCount += 1
                return nil
            }
        )
        let surfaceID = TerminalSurfaceID()

        #expect(cache.agentProcess(surfaceID: surfaceID, processID: 100) == nil)
        // The agent starts under the wrapper without the wrapper changing.
        descendant = TerminalAgentProcessDetector.AgentProcess(
            processID: 101,
            provider: .claudeCode
        )
        let resolved = cache.agentProcess(surfaceID: surfaceID, processID: 100)

        #expect(resolved?.provider == .claudeCode)
        #expect(resolved?.processID == 101)
        // The wrapper itself was only classified once; the scan below it ran
        // on both calls.
        #expect(classifyCount == 1)
        #expect(descendantCount == 2)
    }

    @Test("does not scan below a foreground process that is itself an agent")
    func agentInFrontSkipsDescendantScan() {
        var descendantCount = 0
        let cache = makeCache(
            classifyDescendants: { _ in
                descendantCount += 1
                return nil
            },
            classify: { _ in .codex }
        )
        let surfaceID = TerminalSurfaceID()

        let resolved = cache.agentProcess(surfaceID: surfaceID, processID: 100)

        #expect(resolved?.provider == .codex)
        #expect(resolved?.processID == 100)
        #expect(descendantCount == 0)
    }

    @Test("keeps caches independent per surface")
    func isolatesSurfaces() {
        var classifyCount = 0
        let cache = makeCache { _ in
            classifyCount += 1
            return .codex
        }
        let surfaceA = TerminalSurfaceID()
        let surfaceB = TerminalSurfaceID()

        _ = cache.agentProcess(surfaceID: surfaceA, processID: 100)
        _ = cache.agentProcess(surfaceID: surfaceB, processID: 100)

        #expect(classifyCount == 2)
    }
}
