import AppKit
import MyTTYCore

/// Owns the active `TerminalGIFRecorder` (there is at most one per window)
/// and the save-panel/error/filename plumbing around starting and
/// finishing a recording. Extracted from `TerminalWindowController`'s
/// `startRecording` / `stopRecording` / `recordingOutputURL` /
/// `recordingFailed` / `recordingFilename` verbatim.
///
/// This coordinator captures any `NSView`, not just a terminal surface:
/// `TerminalWindowController` also feeds it `RemotePaneView`, since a
/// mirrored remote pane has no Ghostty surface but is still just a view
/// that can be cached to a bitmap. The caller supplies a `cursorRect`
/// closure for the pressed-key toast instead of this type reaching into
/// `GhosttySurfaceView` itself, which keeps it free of any dependency on
/// `GhosttyAdapter`; remote panes pass `nil` because the client has no
/// local cursor position to draw a toast around.
///
/// The public `toggleRecording()` entry point stays on
/// `TerminalWindowController` because deciding *what* to record (the
/// selected tab's focused surface or remote pane, or failing with
/// `.terminalPaneRequired` if there is neither) reaches into
/// `WindowSession`, `surfaces`, and `remotes`, all controller-private; it
/// resolves those and then calls into this coordinator's `start`/`stop`.
/// Every other call site that used to read `terminalRecorder` directly
/// (sidebar "is recording" rows, closing a tab/pane/window
/// mid-recording, showing the pressed-key toast) now asks this
/// coordinator via its `isRecording`/`noteKey` helpers instead.
@MainActor
final class TerminalRecordingCoordinator {
    private(set) var recorder: TerminalGIFRecorder?
    private var countdownTask: Task<Void, Never>?
    private var pendingCountdown: (tabID: TabID, surfaceID: TerminalSurfaceID)?

    private let showPressedKeyToast: () -> Bool
    /// Read when a recording stops, so the fade reflects the settings at
    /// save time; nil disables the fade.
    private let fadeOut: () -> TerminalRecordingFadeOut?
    private let outputPanelTitle: () -> String
    /// Fired whenever `recorder` starts, stops, or fails — the controller
    /// uses this to refresh the sidebar's recording indicator, mirroring
    /// the `refreshSidebarRows()` calls in the original methods.
    private let onRecordingStateChanged: () -> Void
    private let presentError: (Error) -> Void
    private let countdownEnabled: () -> Bool
    private let showCountdown: (TerminalSurfaceID, Int) -> Void
    private let hideCountdown: (TerminalSurfaceID) -> Void
    private let countdownStepDuration: Duration
    private let window: () -> NSWindow?

    init(
        showPressedKeyToast: @escaping () -> Bool,
        fadeOut: @escaping () -> TerminalRecordingFadeOut?,
        outputPanelTitle: @escaping () -> String,
        onRecordingStateChanged: @escaping () -> Void,
        presentError: @escaping (Error) -> Void,
        countdownEnabled: @escaping () -> Bool,
        showCountdown: @escaping (TerminalSurfaceID, Int) -> Void,
        hideCountdown: @escaping (TerminalSurfaceID) -> Void,
        window: @escaping () -> NSWindow? = { nil },
        countdownStepDuration: Duration = .seconds(1)
    ) {
        self.showPressedKeyToast = showPressedKeyToast
        self.fadeOut = fadeOut
        self.outputPanelTitle = outputPanelTitle
        self.onRecordingStateChanged = onRecordingStateChanged
        self.presentError = presentError
        self.countdownEnabled = countdownEnabled
        self.showCountdown = showCountdown
        self.hideCountdown = hideCountdown
        self.window = window
        self.countdownStepDuration = countdownStepDuration
    }

    var isRecording: Bool { recorder != nil || countdownTask != nil }

    func isRecording(tabID: TabID) -> Bool {
        recorder?.tabID == tabID || pendingCountdown?.tabID == tabID
    }

    func isRecording(surfaceID: TerminalSurfaceID) -> Bool {
        recorder?.surfaceID == surfaceID || pendingCountdown?.surfaceID == surfaceID
    }

    func updateShowPressedKeys(_ showPressedKeys: Bool) {
        recorder?.updateShowPressedKeys(showPressedKeys)
    }

    func noteKey(_ event: NSEvent, forSurface surfaceID: TerminalSurfaceID) {
        guard recorder?.surfaceID == surfaceID else { return }
        recorder?.noteKey(event)
    }

    /// Stops the active recording if it belongs to `tabID`; a no-op
    /// otherwise.
    func stopIfRecording(tabID: TabID) {
        guard isRecording(tabID: tabID) else { return }
        stop()
    }

    /// Stops the active recording if it belongs to `surfaceID`; a no-op
    /// otherwise.
    func stopIfRecording(surfaceID: TerminalSurfaceID) {
        guard isRecording(surfaceID: surfaceID) else { return }
        stop()
    }

    func start(
        tabID: TabID,
        surfaceID: TerminalSurfaceID,
        view: NSView,
        cursorRect: @escaping () -> NSRect?
    ) {
        guard !isRecording else { return }
        guard countdownEnabled() else {
            startRecording(
                tabID: tabID,
                surfaceID: surfaceID,
                view: view,
                cursorRect: cursorRect
            )
            return
        }
        pendingCountdown = (tabID, surfaceID)
        onRecordingStateChanged()
        countdownTask = Task { @MainActor [weak self, weak view] in
            for count in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.showCountdown(surfaceID, count)
                do {
                    try await Task.sleep(for: self.countdownStepDuration)
                } catch {
                    return
                }
            }
            guard let self else { return }
            self.hideCountdown(surfaceID)
            self.countdownTask = nil
            self.pendingCountdown = nil
            guard let view else {
                self.onRecordingStateChanged()
                return
            }
            self.startRecording(
                tabID: tabID,
                surfaceID: surfaceID,
                view: view,
                cursorRect: cursorRect
            )
        }
    }

    private func startRecording(
        tabID: TabID,
        surfaceID: TerminalSurfaceID,
        view: NSView,
        cursorRect: @escaping () -> NSRect?
    ) {
        let recorder = TerminalGIFRecorder(
            tabID: tabID,
            surfaceID: surfaceID,
            view: view,
            showPressedKeys: showPressedKeyToast(),
            keyLabelCursorRect: cursorRect,
            onLimitReached: { [weak self] in
                self?.stop()
            },
            onFailure: { [weak self] error in
                self?.recordingFailed(error)
            }
        )
        do {
            try recorder.start()
            self.recorder = recorder
            onRecordingStateChanged()
        } catch {
            recorder.cancel()
            presentError(error)
        }
    }

    func stop() {
        if let pendingCountdown {
            countdownTask?.cancel()
            countdownTask = nil
            self.pendingCountdown = nil
            hideCountdown(pendingCountdown.surfaceID)
            onRecordingStateChanged()
            return
        }
        guard let recorder else { return }
        self.recorder = nil
        recorder.stopCapturing()
        onRecordingStateChanged()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = recordingFilename()
        panel.title = outputPanelTitle()
        Task { @MainActor [weak self] in
            let response = await ApplicationAlert.present(
                panel,
                on: self?.window()
            )
            guard response == .OK, let outputURL = panel.url else {
                recorder.cancel()
                return
            }
            recorder.finish(to: outputURL, fadeOut: self?.fadeOut()) { result in
                if case let .failure(error) = result {
                    self?.presentError(error)
                }
            }
        }
    }

    private func recordingFailed(_ error: TerminalRecordingError) {
        guard recorder != nil else { return }
        recorder = nil
        onRecordingStateChanged()
        presentError(error)
    }

    private func recordingFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Mytty Recording \(formatter.string(from: Date())).gif"
    }
}
