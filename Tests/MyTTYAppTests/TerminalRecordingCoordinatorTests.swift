import AppKit
import GhosttyAdapter
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Terminal recording coordinator", .serialized)
struct TerminalRecordingCoordinatorTests {
    @Test("starts recording immediately when the countdown is disabled")
    @MainActor
    func countdownDisabled() throws {
        let surface = try Self.makeSurface()
        var stateChangeCount = 0
        var shown: [Int] = []
        var hiddenCount = 0
        let coordinator = TerminalRecordingCoordinator(
            showPressedKeyToast: { false },
            fadeOut: { nil },
            outputPanelTitle: { "" },
            onRecordingStateChanged: { stateChangeCount += 1 },
            presentError: { _ in },
            countdownEnabled: { false },
            showCountdown: { _, count in shown.append(count) },
            hideCountdown: { _ in hiddenCount += 1 },
            countdownStepDuration: .milliseconds(5)
        )
        defer { coordinator.recorder?.cancel() }

        coordinator.start(
            tabID: TabID(),
            surfaceID: TerminalSurfaceID(),
            surface: surface
        )

        #expect(coordinator.isRecording)
        #expect(coordinator.recorder != nil)
        #expect(shown.isEmpty)
        #expect(hiddenCount == 0)
        #expect(stateChangeCount == 1)
    }

    @Test("counts down 3, 2, 1 before recording starts, then hides the overlay")
    @MainActor
    func countdownEnabledStartsRecordingAfterCounting() async throws {
        let surface = try Self.makeSurface()
        let tabID = TabID()
        let surfaceID = TerminalSurfaceID()
        var shown: [Int] = []
        var hiddenCount = 0
        let coordinator = TerminalRecordingCoordinator(
            showPressedKeyToast: { false },
            fadeOut: { nil },
            outputPanelTitle: { "" },
            onRecordingStateChanged: {},
            presentError: { _ in },
            countdownEnabled: { true },
            showCountdown: { _, count in shown.append(count) },
            hideCountdown: { _ in hiddenCount += 1 },
            countdownStepDuration: .milliseconds(5)
        )
        defer { coordinator.recorder?.cancel() }

        coordinator.start(tabID: tabID, surfaceID: surfaceID, surface: surface)

        #expect(coordinator.isRecording)
        #expect(coordinator.isRecording(tabID: tabID))
        #expect(coordinator.isRecording(surfaceID: surfaceID))
        #expect(coordinator.recorder == nil)

        for _ in 0..<400 where coordinator.recorder == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(shown == [3, 2, 1])
        #expect(hiddenCount == 1)
        #expect(coordinator.recorder != nil)
        #expect(coordinator.isRecording)
        #expect(coordinator.isRecording(tabID: tabID))
        #expect(coordinator.isRecording(surfaceID: surfaceID))
    }

    @Test("cancels a pending countdown instead of starting a recording")
    @MainActor
    func stopDuringCountdownCancelsRecording() async throws {
        let surface = try Self.makeSurface()
        var hiddenCount = 0
        var stateChangeCount = 0
        let coordinator = TerminalRecordingCoordinator(
            showPressedKeyToast: { false },
            fadeOut: { nil },
            outputPanelTitle: { "" },
            onRecordingStateChanged: { stateChangeCount += 1 },
            presentError: { _ in },
            countdownEnabled: { true },
            showCountdown: { _, _ in },
            hideCountdown: { _ in hiddenCount += 1 },
            countdownStepDuration: .milliseconds(30)
        )

        coordinator.start(
            tabID: TabID(),
            surfaceID: TerminalSurfaceID(),
            surface: surface
        )
        #expect(coordinator.isRecording)
        #expect(stateChangeCount == 1)

        coordinator.stop()

        #expect(!coordinator.isRecording)
        #expect(coordinator.recorder == nil)
        #expect(hiddenCount == 1)
        #expect(stateChangeCount == 2)

        // Let the in-flight countdown Task resume after cancellation; it
        // must not still start a recording behind the coordinator's back.
        try await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.recorder == nil)
        #expect(!coordinator.isRecording)
    }

    @MainActor
    private static func makeSurface() throws -> GhosttySurfaceView {
        try GhosttyLibrary.initializeCurrentProcess()
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
        let configuration = try GhosttyConfiguration(file: file)
        let runtime = try GhosttyRuntime(configuration: configuration)
        let surface = try GhosttySurfaceView(runtime: runtime)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = surface
        return surface
    }
}
