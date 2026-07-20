import AppKit
import Foundation
import Testing

@testable import GhosttyAdapter

@Suite("Ghostty surface integration", .serialized)
struct GhosttySurfaceIntegrationTests {
    @Test("opens and closes native terminal search")
    @MainActor
    func searchPresentation() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(runtime: runtime)

        surface.showSearch()
        for _ in 0..<100 where !surface.isSearchPresented {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(surface.isSearchPresented)

        surface.closeSearch()
        for _ in 0..<100 where surface.isSearchPresented {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!surface.isSearchPresented)
    }

    @Test("represents a URL open request as a surface event")
    func openURLRequestEvent() {
        let url = URL(string: "https://example.com/documentation")!

        #expect(GhosttySurfaceEvent.openURLRequested(url) == .openURLRequested(url))
    }

    @Test("routes application shortcuts before terminal input")
    @MainActor
    func applicationShortcut() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent()
        )
        let target = ShortcutTarget()
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let settingsItem = applicationMenu.addItem(
            withTitle: "Settings...",
            action: #selector(ShortcutTarget.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = target
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let previousMenu = NSApplication.shared.mainMenu
        NSApplication.shared.mainMenu = mainMenu
        defer { NSApplication.shared.mainMenu = previousMenu }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43
        ))

        #expect(surface.performKeyEquivalent(with: event))
        #expect(target.openCount == 1)
    }

    @Test("builds a right-click menu with localized editing actions")
    @MainActor
    func contextMenu() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            contextMenuLabels: GhosttyContextMenuLabels(
                copy: "コピー",
                paste: "ペースト",
                selectAll: "すべてを選択",
                closePane: "ペインを閉じる"
            )
        )
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        let menu = try #require(surface.menu(for: event))

        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            == ["ペースト", "すべてを選択", "ペインを閉じる"])
    }

    @Test("builds standard native actions for selected terminal text")
    @MainActor
    func selectedTextContextMenu() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            contextMenuLabels: GhosttyContextMenuLabels(
                copy: "コピー",
                paste: "ペースト",
                selectAll: "すべてを選択",
                lookUpSelectionFormat: "“%@”を調べる",
                searchWithGoogle: "Google で検索",
                share: "共有",
                services: "サービス",
                closePane: "ペインを閉じる"
            )
        )

        let menu = surface.makeContextMenu(
            selectionText: "hello world",
            location: .zero
        )
        let items = menu.items.filter { !$0.isSeparatorItem }

        #expect(items.map(\.title) == [
            "“hello world”を調べる",
            "Google で検索",
            "コピー",
            "ペースト",
            "すべてを選択",
            "共有",
            "サービス",
            "ペインを閉じる",
        ])
        let servicesItem = items[items.count - 2]
        #expect(servicesItem.submenu != nil)
        #expect(NSApplication.shared.servicesMenu === servicesItem.submenu)
    }

    @Test("draws immediately after a surface resize")
    @MainActor
    func immediateDrawAfterResize() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(runtime: runtime)

        surface.setFrameSize(NSSize(width: 420, height: 280))
        surface.drawImmediately()

        #expect(surface.frame.size == NSSize(width: 420, height: 280))
        #expect(surface.rendererIsHealthy)
    }

    @Test("keeps valid terminal geometry during a transient zero layout")
    @MainActor
    func transientZeroGeometry() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let initialSize = NSSize(width: 320, height: 240)
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            initialSize: initialSize
        )
        let appliedSize = surface.terminalBackingSize

        #expect(surface.bounds.size == initialSize)
        #expect(appliedSize.width > 0)
        #expect(appliedSize.height > 0)

        surface.setFrameSize(.zero)

        #expect(surface.terminalBackingSize == appliedSize)
    }

    @Test("reports the terminal grid after geometry changes")
    @MainActor
    func terminalGridSize() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            initialSize: NSSize(width: 320, height: 240)
        )
        let initialGrid = surface.terminalGridSize

        #expect(initialGrid.columns > 0)
        #expect(initialGrid.rows > 0)

        surface.setFrameSize(NSSize(width: 640, height: 240))

        #expect(surface.terminalGridSize.columns > initialGrid.columns)
        #expect(surface.terminalGridSize.rows == initialGrid.rows)
    }

    @Test("reports the foreground process for its PTY")
    @MainActor
    func foregroundProcessID() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(runtime: runtime)

        var processID: pid_t = 0
        for _ in 0..<100 {
            processID = surface.foregroundProcessID
            if processID > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(processID > 0)
    }

    @Test("redraws an inactive surface after its geometry changes")
    func inactiveResizeRedrawPolicy() {
        #expect(
            GhosttySurfaceView.shouldDrawImmediatelyAfterResize(
                isFocused: false
            )
        )
        #expect(
            !GhosttySurfaceView.shouldDrawImmediatelyAfterResize(
                isFocused: true
            )
        )
    }

    @Test("reattaching a surface preserves the selected terminal focus")
    @MainActor
    func reattachmentPreservesFocus() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let reattachedSurface = try GhosttySurfaceView(runtime: runtime)
        let selectedSurface = try GhosttySurfaceView(runtime: runtime)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.addSubview(reattachedSurface)
        host.addSubview(selectedSurface)
        #expect(window.makeFirstResponder(selectedSurface))

        reattachedSurface.removeFromSuperview()
        host.addSubview(reattachedSurface)

        #expect(window.firstResponder === selectedSurface)
    }

    @Test("a background surface does not consume terminal key equivalents")
    @MainActor
    func backgroundSurfaceDoesNotConsumeKeyEquivalent() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let backgroundSurface = try GhosttySurfaceView(runtime: runtime)
        let selectedSurface = try GhosttySurfaceView(runtime: runtime)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.addSubview(backgroundSurface)
        host.addSubview(selectedSurface)
        #expect(window.makeFirstResponder(selectedSurface))
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{4}",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))

        #expect(!backgroundSurface.performKeyEquivalent(with: event))
    }

    @Test("explicit focus state reaches the embedded terminal")
    @MainActor
    func explicitFocusState() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(runtime: runtime)

        #expect(surface.isTerminalFocused)

        surface.setFocused(false)

        #expect(!surface.isTerminalFocused)

        surface.setFocused(true)

        #expect(surface.isTerminalFocused)
    }

    @Test("round trips initial input through the shell and terminal screen")
    @MainActor
    func shellRoundTrip() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let marker = "mytty-surface-round-trip"
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "printf '\(marker)\\n'\n"
        )

        var contents = ""
        for _ in 0..<100 {
            contents = surface.visibleText()
            if contents.contains(marker) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(contents.contains(marker))
    }

    @Test("reads visible text from a surface detached from its window, as background tabs are")
    @MainActor
    func visibleTextAfterDetachingFromWindow() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let marker = "mytty-detached-surface-content"
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "printf '\(marker)\\n'\n"
        )

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.addSubview(surface)
        surface.frame = host.bounds

        var contents = ""
        for _ in 0..<100 {
            contents = surface.visibleText()
            if contents.contains(marker) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(contents.contains(marker))

        // Mirrors what TerminalWindowController.attachSelectedTab does to
        // every surface belonging to a tab the user switches away from.
        surface.removeFromSuperview()

        let detachedContents = surface.visibleText()
        #expect(detachedContents.contains(marker))
    }

    @Test("reports the cursor grid position on the prompt line")
    @MainActor
    func cursorGridPosition() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let marker = "mytty-cursor-position"
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "printf '\(marker)\\n'\n"
        )

        var contents = ""
        for _ in 0..<100 {
            contents = surface.visibleText()
            if contents.contains(marker) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(200))
        contents = surface.visibleText()

        let position = try #require(surface.terminalCursorPosition)
        let grid = surface.terminalGridSize
        FileHandle.standardError.write(Data(
            "[cursor] row=\(position.row) col=\(position.column) grid=\(grid) lines=\(contents.split(separator: "\n", omittingEmptySubsequences: false).count)\n".utf8
        ))
        #expect((0..<grid.rows).contains(position.row))
        #expect((0..<grid.columns).contains(position.column))
        #expect(position.column > 0)
        #expect(position.column + 3 < grid.columns)

        // Typing three single-cell ASCII characters without submitting
        // must move the cursor exactly three cells on the same row. This
        // directly verifies the coordinates used by the remote client's
        // block cursor without assuming that Ghostty's selected text
        // preserves blank viewport rows on every macOS version.
        surface.sendText("abc")
        var typedPosition = position
        for _ in 0..<100 {
            typedPosition = try #require(surface.terminalCursorPosition)
            if typedPosition.row == position.row,
               typedPosition.column == position.column + 3 {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        FileHandle.standardError.write(Data(
            "[cursor] after-typing row=\(typedPosition.row) col=\(typedPosition.column) expected-col=\(position.column + 3)\n".utf8
        ))
        #expect(typedPosition.row == position.row)
        #expect(typedPosition.column == position.column + 3)
    }

    @Test("screen text includes scrollback that left the viewport")
    @MainActor
    func screenTextIncludesScrollback() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let doneMarker = "mytty-scrollback-done"
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "for i in $(seq 1 60); do echo scroll-line-$i; done; printf '\(doneMarker)\\n'\n"
        )

        // Wait for the loop's *output* (not the echoed command line,
        // which also contains the marker text) to finish rendering.
        var visible = ""
        for _ in 0..<100 {
            visible = surface.visibleText()
            if visible.contains("scroll-line-60") {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(visible.contains("scroll-line-60"))

        // Sixty output lines exceed the default grid height, so the
        // first line has scrolled out of the viewport but must still be
        // present in the full screen text.
        #expect(!visible.contains("scroll-line-1\n"))
        let screen = surface.screenText()
        #expect(screen.contains("scroll-line-1\n"))
        #expect(screen.contains(doneMarker))
    }

    @Test("captures and replays scrollback with VT color attributes")
    @MainActor
    func coloredScrollbackRoundTrip() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let marker = "mytty-colored-history"
        let source = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "printf '\\033[31m\(marker)\\033[0m\\n'\n"
        )

        for _ in 0..<100 where !source.screenText().contains(marker) {
            try await Task.sleep(for: .milliseconds(50))
        }
        let history = source.screenVTText()
        #expect(history.contains(marker))
        #expect(history.contains("\u{1B}["))

        let restored = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            restoredTerminalHistory: history
        )

        for _ in 0..<100 where !restored.screenText().contains(marker) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(restored.screenText().contains(marker))
        let replayedHistory = restored.screenVTText()
        #expect(replayedHistory.contains(marker))
        #expect(replayedHistory.contains("\u{1B}["))
    }

    @Test("sends programmatic text to a running shell")
    @MainActor
    func programmaticText() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let marker = "mytty-programmatic-output"
        let escapedMarker = marker.utf8.map {
            String(format: "\\%03o", $0)
        }.joined()
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent()
        )

        try await Task.sleep(for: .milliseconds(200))
        surface.sendText("printf '\(escapedMarker)\\n'")
        surface.sendEnter()

        var contents = ""
        for _ in 0..<40 {
            contents = surface.visibleText()
            if contents.contains(marker) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(contents.contains(marker))
    }

    @Test("passes surface-scoped environment to the shell")
    @MainActor
    func surfaceEnvironment() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let marker = "surface-capability-marker"
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "printf '%s\\n' \"$MYTTY_SURFACE_ID\"\n",
            environmentVariables: ["MYTTY_SURFACE_ID": marker]
        )

        var contents = ""
        for _ in 0..<100 {
            contents = surface.visibleText()
            if contents.contains(marker) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(contents.contains(marker))
    }

    @Test("reports a successful shell command with its exit code")
    @MainActor
    func commandFinishedEvent() async throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try """
        font-size = 13
        command = /bin/zsh
        shell-integration = none
        """.appending("\n").write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: file.deletingLastPathComponent(),
            initialInput: "printf '\\033]133;C\\007'; sleep 1; "
                + "printf '\\033]133;D;0\\007'\n",
            environmentVariables: [
                "HOME": file.deletingLastPathComponent().path,
            ]
        )
        var result: (exitCode: Int?, durationNanoseconds: UInt64)?
        surface.onEvent = { event in
            switch event {
            case let .commandFinished(exitCode, durationNanoseconds):
                result = (exitCode, durationNanoseconds)
            default:
                break
            }
        }

        for _ in 0..<500 where result == nil {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(result?.exitCode == 0)
        #expect(result?.durationNanoseconds ?? 0 > 0)
    }

    @Test("shows and hides a faded autocomplete suggestion")
    @MainActor
    func autocompleteSuggestionOverlay() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(runtime: runtime)

        surface.setAutocompleteSuggestion("cd aaa")

        #expect(surface.autocompleteSuggestionText == "cd aaa")

        surface.setAutocompleteSuggestion(nil)

        #expect(surface.autocompleteSuggestionText == nil)
    }

    @Test("lets autocomplete consume Tab before terminal input")
    @MainActor
    func autocompleteKeyInterception() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(runtime: runtime)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))
        var intercepted = 0
        surface.onKeyIntercept = { _ in
            intercepted += 1
            return true
        }

        surface.keyDown(with: event)

        #expect(intercepted == 1)
    }

    private func temporaryConfiguration() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("terminal.conf")
        try "font-size = 13\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        return file
    }
}

@MainActor
private final class ShortcutTarget: NSObject {
    private(set) var openCount = 0

    @objc func openSettings(_ sender: Any?) {
        openCount += 1
    }
}
