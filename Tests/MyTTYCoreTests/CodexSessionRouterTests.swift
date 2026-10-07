import Foundation
import Testing

@testable import MyTTYCore

@Suite("Codex session router")
struct CodexSessionRouterTests {
    private let repo = URL(fileURLWithPath: "/tmp/mytty-router-tests/repo")
    private let other = URL(fileURLWithPath: "/tmp/mytty-router-tests/other")

    private func pane(
        _ surface: TerminalSurfaceID,
        pid: pid_t,
        bound: String? = nil,
        launch: String? = nil,
        cwd: URL? = nil
    ) -> CodexPaneCandidate {
        CodexPaneCandidate(
            surfaceID: surface,
            processID: pid,
            processBoundSessionID: bound,
            launchSessionID: launch,
            workingDirectory: cwd
        )
    }

    private func metadata(
        _ table: [String: URL]
    ) -> (String) -> CodexSessionMetadata? {
        { id in
            table[id].map {
                CodexSessionMetadata(sessionID: id, workingDirectory: $0)
            }
        }
    }

    @Test("routes two concurrent sessions to their own panes")
    func twoSessions() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        let b = TerminalSurfaceID()
        let panes = [
            pane(a, pid: 10, cwd: repo),
            pane(b, pid: 11, cwd: other),
        ]
        let table = ["s1": repo, "s2": other]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: true,
                candidates: panes, metadata: metadata(table)
            ) == a
        )
        #expect(
            router.resolve(
                sessionID: "s2", opensSession: true,
                candidates: panes, metadata: metadata(table)
            ) == b
        )
        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: panes, metadata: { _ in nil }
            ) == a
        )
    }

    @Test("keeps a claim without consulting metadata again")
    func claimIsRemembered() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        let panes = [pane(a, pid: 10, cwd: repo)]
        _ = router.resolve(
            sessionID: "s1", opensSession: true,
            candidates: panes, metadata: metadata(["s1": repo])
        )

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: panes, metadata: { _ in nil }
            ) == a
        )
    }

    @Test("rejects a session whose pane has closed")
    func paneClosed() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        let table = metadata(["s1": repo])
        _ = router.resolve(
            sessionID: "s1", opensSession: true,
            candidates: [pane(a, pid: 10, cwd: repo)], metadata: table
        )

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: [], metadata: table
            ) == nil
        )
        // The claim is gone, so a new pane in the same directory does not
        // inherit it without a fresh claim from metadata.
        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: [pane(TerminalSurfaceID(), pid: 12, cwd: repo)],
                metadata: { _ in nil }
            ) == nil
        )
    }

    @Test("rejects a session after its pane's process id changed")
    func processReplaced() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        _ = router.resolve(
            sessionID: "s1", opensSession: true,
            candidates: [pane(a, pid: 10, cwd: repo)],
            metadata: metadata(["s1": repo])
        )

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: [pane(a, pid: 99, cwd: repo)],
                metadata: { _ in nil }
            ) == nil
        )
    }

    @Test("rejects when two unbound panes share the working directory")
    func ambiguous() {
        var router = CodexSessionRouter()
        let panes = [
            pane(TerminalSurfaceID(), pid: 10, cwd: repo),
            pane(TerminalSurfaceID(), pid: 11, cwd: repo),
        ]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: true,
                candidates: panes, metadata: metadata(["s1": repo])
            ) == nil
        )
    }

    @Test("a process-bound pane wins over an existing claim")
    func processBoundBeatsClaim() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        let b = TerminalSurfaceID()
        _ = router.resolve(
            sessionID: "s1", opensSession: true,
            candidates: [pane(a, pid: 10, cwd: repo)],
            metadata: metadata(["s1": repo])
        )

        let resolved = router.resolve(
            sessionID: "s1", opensSession: false,
            candidates: [
                pane(a, pid: 10, bound: "s2", cwd: repo),
                pane(b, pid: 11, bound: "s1", cwd: repo),
            ],
            metadata: { _ in nil }
        )
        #expect(resolved == b)
    }

    @Test("a claim stops resolving once its pane is process-bound elsewhere")
    func claimConflictsWithProcessBinding() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        _ = router.resolve(
            sessionID: "s1", opensSession: true,
            candidates: [pane(a, pid: 10, cwd: repo)],
            metadata: metadata(["s1": repo])
        )

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: [pane(a, pid: 10, bound: "s2", cwd: repo)],
                metadata: { _ in nil }
            ) == nil
        )
    }

    @Test("rejects a session bound to more than one process")
    func duplicateProcessBinding() {
        var router = CodexSessionRouter()
        let panes = [
            pane(TerminalSurfaceID(), pid: 10, bound: "s1", cwd: repo),
            pane(TerminalSurfaceID(), pid: 11, bound: "s1", cwd: repo),
        ]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: panes, metadata: metadata(["s1": repo])
            ) == nil
        )
    }

    @Test("binds a session named by the resume argument without metadata")
    func resumeArgument() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        let panes = [
            pane(a, pid: 10, launch: "s1", cwd: other),
            pane(TerminalSurfaceID(), pid: 11, cwd: repo),
        ]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: panes, metadata: { _ in nil }
            ) == a
        )
    }

    @Test("a resume binding goes stale once a new session takes the pane")
    func resumeArgumentAlreadyTakenOver() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        let panes = [pane(a, pid: 10, launch: "old", cwd: repo)]
        // /new inside the TUI: the new session replaces the stale binding.
        #expect(
            router.resolve(
                sessionID: "new", opensSession: true,
                candidates: panes, metadata: metadata(["new": repo])
            ) == a
        )

        #expect(
            router.resolve(
                sessionID: "old", opensSession: false,
                candidates: panes, metadata: metadata(["old": repo])
            ) == nil
        )
        #expect(
            router.resolve(
                sessionID: "new", opensSession: false,
                candidates: panes, metadata: { _ in nil }
            ) == a
        )
    }

    @Test("a new session in the same pane replaces a stale claim only on a session-opening event")
    func sessionStartReclaims() {
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()
        let panes = [pane(a, pid: 10, cwd: repo)]
        let table = metadata(["s1": repo, "s2": repo])
        _ = router.resolve(
            sessionID: "s1", opensSession: true,
            candidates: panes, metadata: table
        )

        #expect(
            router.resolve(
                sessionID: "s2", opensSession: false,
                candidates: panes, metadata: table
            ) == nil
        )
        #expect(
            router.resolve(
                sessionID: "s2", opensSession: true,
                candidates: panes, metadata: table
            ) == a
        )
        // The pane now belongs to s2; s1 no longer resolves.
        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: panes, metadata: table
            ) == nil
        )
    }

    @Test("a session-opening event does not take over a process-bound pane")
    func sessionStartLeavesProcessBoundPane() {
        var router = CodexSessionRouter()
        let panes = [pane(TerminalSurfaceID(), pid: 10, bound: "s1", cwd: repo)]

        #expect(
            router.resolve(
                sessionID: "s2", opensSession: true,
                candidates: panes, metadata: metadata(["s2": repo])
            ) == nil
        )
    }

    @Test("skips panes bound to another session when claiming by directory")
    func skipsOtherBindings() {
        var router = CodexSessionRouter()
        let free = TerminalSurfaceID()
        let panes = [
            pane(TerminalSurfaceID(), pid: 10, bound: "x", cwd: repo),
            pane(TerminalSurfaceID(), pid: 11, launch: "y", cwd: repo),
            pane(free, pid: 12, cwd: repo),
        ]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: false,
                candidates: panes, metadata: metadata(["s1": repo])
            ) == free
        )
    }

    @Test("rejects when metadata is unavailable")
    func noMetadata() {
        var router = CodexSessionRouter()
        let panes = [pane(TerminalSurfaceID(), pid: 10, cwd: repo)]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: true,
                candidates: panes, metadata: { _ in nil }
            ) == nil
        )
    }

    @Test("rejects metadata that names a different session")
    func metadataForAnotherSession() {
        var router = CodexSessionRouter()
        let panes = [pane(TerminalSurfaceID(), pid: 10, cwd: repo)]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: true,
                candidates: panes,
                metadata: { _ in
                    CodexSessionMetadata(sessionID: "s2", workingDirectory: repo)
                }
            ) == nil
        )
    }

    @Test("rejects when no pane is in the session's working directory")
    func differentDirectory() {
        var router = CodexSessionRouter()
        let panes = [
            pane(TerminalSurfaceID(), pid: 10, cwd: other),
            pane(TerminalSurfaceID(), pid: 11),
        ]

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: true,
                candidates: panes, metadata: metadata(["s1": repo])
            ) == nil
        )
    }

    @Test("compares working directories after resolving symlinks")
    func symlinkedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let real = root.appendingPathComponent("real", isDirectory: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(
            at: real, withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: real
        )
        defer { try? FileManager.default.removeItem(at: root) }
        var router = CodexSessionRouter()
        let a = TerminalSurfaceID()

        #expect(
            router.resolve(
                sessionID: "s1", opensSession: true,
                candidates: [pane(a, pid: 10, cwd: real)],
                metadata: metadata(["s1": link])
            ) == a
        )
    }

    @Test("resolves uniquely among panes gathered from several windows")
    func manyPanes() {
        var router = CodexSessionRouter()
        let surfaces = (0..<6).map { _ in TerminalSurfaceID() }
        let dirs = (0..<6).map {
            URL(fileURLWithPath: "/tmp/mytty-router-tests/dir\($0)")
        }
        let panes = (0..<6).map {
            pane(surfaces[$0], pid: pid_t(100 + $0), cwd: dirs[$0])
        }
        let table = Dictionary(
            uniqueKeysWithValues: (0..<6).map { ("s\($0)", dirs[$0]) }
        )

        for index in [4, 1, 5, 0, 3, 2] {
            #expect(
                router.resolve(
                    sessionID: "s\(index)", opensSession: true,
                    candidates: panes, metadata: metadata(table)
                ) == surfaces[index]
            )
        }
    }
}
