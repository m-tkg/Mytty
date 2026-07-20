import Foundation
import Testing

@testable import MyTTYCore

@Suite("Session repository", .serialized)
struct SessionRepositoryTests {
    @Test("returns no snapshot before the first save")
    func emptyRepository() throws {
        let fixture = makeRepository()
        defer { fixture.remove() }

        let snapshot = try fixture.repository.load()

        #expect(snapshot == nil)
    }

    @Test("round trips windows, tabs, splits, focus, and directories")
    func roundTrip() throws {
        let fixture = makeRepository()
        defer { fixture.remove() }
        let snapshot = try makeSnapshot(path: "/repo")

        try fixture.repository.save(snapshot)
        let restored = try fixture.repository.load()

        #expect(restored == snapshot)
    }

    @Test("replaces the previous snapshot")
    func replacesSnapshot() throws {
        let fixture = makeRepository()
        defer { fixture.remove() }
        let first = try makeSnapshot(path: "/first")
        let second = try makeSnapshot(path: "/second")

        try fixture.repository.save(first)
        try fixture.repository.save(second)

        #expect(try fixture.repository.load() == second)
    }

    @Test("preserves the last window frame without open windows")
    func preservesLastWindowFrame() throws {
        let fixture = makeRepository()
        defer { fixture.remove() }
        let frame = WindowFrame(
            x: 100,
            y: 120,
            width: 1234,
            height: 777
        )

        try fixture.repository.save(
            SessionSnapshot(windows: [], lastWindowFrame: frame)
        )

        let restored = try fixture.repository.load()
        #expect(restored?.windows.isEmpty == true)
        #expect(restored?.lastWindowFrame == frame)
    }

    @Test("decodes sessions saved before agent resume metadata existed")
    func backwardsCompatibleAgentResumeMetadata() throws {
        let state = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/repo", isDirectory: true)
        )
        let encoded = try JSONEncoder().encode(state)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "agentResume")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(
            TerminalSurfaceState.self,
            from: legacyData
        )

        #expect(restored.agentResume == nil)
    }

    @Test("round trips ANSI terminal history")
    func terminalHistoryRoundTrip() throws {
        let history = "\u{1B}[31mred\u{1B}[0m\r\nplain"
        let state = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/repo", isDirectory: true),
            terminalHistory: history
        )

        let encoded = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(
            TerminalSurfaceState.self,
            from: encoded
        )

        #expect(restored.terminalHistory == history)
    }

    @Test("decodes sessions saved before terminal history existed")
    func backwardsCompatibleTerminalHistory() throws {
        let legacyData = Data(
            #"{"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"workingDirectory":"file:\/\/\/repo\/"}"#.utf8
        )

        let restored = try JSONDecoder().decode(
            TerminalSurfaceState.self,
            from: legacyData
        )

        #expect(restored.terminalHistory == nil)
    }

    private func makeSnapshot(path: String) throws -> SessionSnapshot {
        let first = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(1)),
            workingDirectory: URL(fileURLWithPath: path, isDirectory: true),
            agentResume: AgentResumeDescriptor(
                kind: .codex,
                sessionID: "codex-session-01"
            )
        )
        let second = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(2)),
            workingDirectory: URL(
                fileURLWithPath: path + "/nested",
                isDirectory: true
            )
        )
        var tab = TabSession(
            id: TabID(rawValue: makeUUID(3)),
            initialSurface: first,
            pinnedTitle: "Pinned"
        )
        try tab.split(surface: first.id, adding: second, direction: .right)
        try tab.split(
            browser: BrowserPaneState(
                id: TerminalSurfaceID(rawValue: makeUUID(5)),
                url: URL(fileURLWithPath: path + "/report.html")
            ),
            direction: .down
        )

        let window = WindowSession(
            id: WindowID(rawValue: makeUUID(4)),
            frame: WindowFrame(x: 100, y: 120, width: 1100, height: 720),
            tabs: [tab],
            selectedTabID: tab.id
        )
        return SessionSnapshot(windows: [window])
    }

    private func makeRepository() -> RepositoryFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let database = directory.appendingPathComponent("mytty.sqlite")
        return RepositoryFixture(
            directory: directory,
            repository: SQLiteSessionRepository(databaseURL: database)
        )
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }
}

private struct RepositoryFixture {
    let directory: URL
    let repository: SQLiteSessionRepository

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
