import AppKit
import Foundation
import Testing

@testable import GhosttyAdapter

// Regression coverage for the remote cursor drifting off its cell: the
// old `terminalCursorPosition` divided the IME caret's pixel point by the
// cell size, which reported the row one below the real cursor, so every
// cursor-anchored read landed in the blank region under the prompt (the
// suffix read came back empty and the remote column froze at the line's
// length — visible as "press delete, the character disappears but the
// cursor doesn't move").
@Suite("Cursor grid position", .serialized)
struct CursorGridPositionTests {
    @Test("the cursor grid position is absolute, not derived from pixels")
    @MainActor
    func cursorPositionIsAbsolute() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        // `clear` resets the grid so the cursor's coordinates are exactly
        // where `printf` leaves them, with no banner or prompt rows above;
        // `sleep` keeps the shell from painting a fresh prompt over it.
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "clear; printf 'ab'; sleep 30\n"
        )

        var position: GhosttyGridPosition?
        for _ in 0..<100 {
            position = surface.terminalCursorPosition
            if surface.visibleText() == "ab", position?.column == 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let cursor = try #require(position)
        FileHandle.standardError.write(Data(
            "[cursor-abs] position=\(cursor) visible=<\(surface.visibleText())>\n".utf8
        ))
        #expect(cursor.row == 0)
        #expect(cursor.column == 2)
        #expect(surface.visibleTextFromCursor() == "")
    }

    @Test("delete pulls the cursor column back through overwritten spaces")
    @MainActor
    func deleteMovesCursorColumn() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let marker = "mytty-cursor-delete"
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "printf '\(marker)\\n'\n"
        )

        for _ in 0..<100 {
            if surface.visibleText().contains(marker) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        var position = try #require(surface.terminalCursorPosition)
        for _ in 0..<100 where position.column == 0 {
            try await Task.sleep(for: .milliseconds(50))
            position = try #require(surface.terminalCursorPosition)
        }
        let promptColumn = position.column

        surface.sendTypedText("aaa")
        for _ in 0..<100 {
            position = try #require(surface.terminalCursorPosition)
            if position.column == promptColumn + 3 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(position.column == promptColumn + 3)
        // Nothing is written at or after the cursor, so the suffix read
        // that anchors the remote cursor must be empty here.
        #expect(surface.visibleTextFromCursor() == "")

        // The shell erases with backspace-space-backspace, which leaves a
        // *written* space under the cursor: the column must still step
        // back, and the suffix read must see that written space instead
        // of coming back empty (the frozen-cursor regression).
        surface.sendKeyPress(keyCode: 51, characters: "\u{7f}")
        for _ in 0..<100 {
            position = try #require(surface.terminalCursorPosition)
            if position.column == promptColumn + 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(position.column == promptColumn + 2)
        let suffix = try #require(surface.visibleTextFromCursor())
        #expect(suffix.allSatisfy { $0 == " " })

        surface.sendKeyPress(keyCode: 51, characters: "\u{7f}")
        for _ in 0..<100 {
            position = try #require(surface.terminalCursorPosition)
            if position.column == promptColumn + 1 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(position.column == promptColumn + 1)
    }

    private func temporaryConfiguration() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("terminal.conf")
        // `zsh -f` keeps test shells away from the developer's rc files
        // and real `~/.zsh_history` (see GhosttySurfaceIntegrationTests).
        try "font-size = 13\ncommand = direct:/bin/zsh -f\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        return file
    }
}
