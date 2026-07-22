import AppKit
import Testing

@testable import MyTTYApp

@Suite("Window session coordination")
struct WindowSessionCoordinatorTests {
    @MainActor
    private static func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    @MainActor
    @Test("returns the key window when it is a candidate")
    func keyWindowIsCandidate() {
        let key = Self.makeWindow()
        let other = Self.makeWindow()

        let result = WindowSessionCoordinator.composerTargetWindow(
            keyWindow: key,
            mainWindow: other,
            candidates: [key, other]
        )

        #expect(result === key)
    }

    @MainActor
    @Test("falls back to the main window when the key window is a panel not among the candidates")
    func keyWindowNotCandidateFallsBackToMain() {
        let panel = Self.makeWindow()
        let main = Self.makeWindow()
        let other = Self.makeWindow()

        let result = WindowSessionCoordinator.composerTargetWindow(
            keyWindow: panel,
            mainWindow: main,
            candidates: [main, other]
        )

        #expect(result === main)
    }

    @MainActor
    @Test("returns nil when neither the key window nor the main window is a candidate")
    func neitherKeyNorMainIsCandidate() {
        let panel = Self.makeWindow()
        let unrelatedMain = Self.makeWindow()
        let candidate = Self.makeWindow()

        let resultWithUnrelatedMain = WindowSessionCoordinator
            .composerTargetWindow(
                keyWindow: panel,
                mainWindow: unrelatedMain,
                candidates: [candidate]
            )
        #expect(resultWithUnrelatedMain == nil)

        let resultWithNilMain = WindowSessionCoordinator.composerTargetWindow(
            keyWindow: panel,
            mainWindow: nil,
            candidates: [candidate]
        )
        #expect(resultWithNilMain == nil)
    }

    @MainActor
    @Test("returns the first candidate when there is no key window at all")
    func noKeyWindowReturnsFirstCandidate() {
        let first = Self.makeWindow()
        let second = Self.makeWindow()

        let result = WindowSessionCoordinator.composerTargetWindow(
            keyWindow: nil,
            mainWindow: second,
            candidates: [first, second]
        )

        #expect(result === first)
    }
}
