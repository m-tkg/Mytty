import AppKit
import GhosttyAdapter
import MyTTYCore

/// Owns the active `TerminalGIFRecorder` (there is at most one per window)
/// and the save-panel/error/filename plumbing around starting and
/// finishing a recording. Extracted from `TerminalWindowController`'s
/// `startRecording` / `stopRecording` / `recordingOutputURL` /
/// `recordingFailed` / `recordingFilename` verbatim.
///
/// The public `toggleRecording()` entry point stays on
/// `TerminalWindowController` because deciding *what* to record (the
/// selected tab's focused surface, or failing with
/// `.terminalPaneRequired` if there is none) reaches into `WindowSession`
/// and `surfaces`, both controller-private; it resolves those and then
/// calls into this coordinator's `start`/`stop`. Every other call site
/// that used to read `terminalRecorder` directly (sidebar "is recording"
/// rows, closing a tab/pane/window mid-recording, showing the pressed-key
/// toast) now asks this coordinator via its `isRecording`/`noteKey`
/// helpers instead.
@MainActor
final class TerminalRecordingCoordinator {
    private(set) var recorder: TerminalGIFRecorder?

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

    init(
        showPressedKeyToast: @escaping () -> Bool,
        fadeOut: @escaping () -> TerminalRecordingFadeOut?,
        outputPanelTitle: @escaping () -> String,
        onRecordingStateChanged: @escaping () -> Void,
        presentError: @escaping (Error) -> Void
    ) {
        self.showPressedKeyToast = showPressedKeyToast
        self.fadeOut = fadeOut
        self.outputPanelTitle = outputPanelTitle
        self.onRecordingStateChanged = onRecordingStateChanged
        self.presentError = presentError
    }

    var isRecording: Bool { recorder != nil }

    func isRecording(tabID: TabID) -> Bool {
        recorder?.tabID == tabID
    }

    func isRecording(surfaceID: TerminalSurfaceID) -> Bool {
        recorder?.surfaceID == surfaceID
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
        surface: GhosttySurfaceView
    ) {
        let recorder = TerminalGIFRecorder(
            tabID: tabID,
            surfaceID: surfaceID,
            view: surface,
            showPressedKeys: showPressedKeyToast(),
            keyLabelCursorRect: { [weak surface] in
                surface?.terminalCursorRect
            },
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
        guard let recorder else { return }
        self.recorder = nil
        recorder.stopCapturing()
        onRecordingStateChanged()
        guard let outputURL = recordingOutputURL() else {
            recorder.cancel()
            return
        }
        recorder.finish(to: outputURL, fadeOut: fadeOut()) { [weak self] result in
            if case let .failure(error) = result {
                self?.presentError(error)
            }
        }
    }

    private func recordingOutputURL() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = recordingFilename()
        panel.title = outputPanelTitle()
        guard panel.runModal() == .OK else { return nil }
        return panel.url
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
