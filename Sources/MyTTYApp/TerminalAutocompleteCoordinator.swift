import AppKit
import GhosttyAdapter
import MyTTYCore

/// Owns per-surface autocomplete state: the `TerminalAutocompleteSession`
/// state machines and the short-lived presentation tasks that debounce
/// showing/hiding a suggestion. Extracted from `TerminalWindowController`
/// verbatim — the debounce delays (10ms after a keystroke, 60ms after a
/// command finishes), the task-cancellation-on-every-call pattern, and the
/// "hide" short-circuit that skips scheduling a task altogether are
/// unchanged.
///
/// `TerminalWindowController` owns this coordinator and supplies live
/// surface lookups via closures (`surfaces` is controller-private) rather
/// than this type reaching into it directly. It has no timer of its own —
/// each presentation task is scoped to a single key/command event and
/// self-cancels via its stored `Task` handle, exactly as before.
@MainActor
final class TerminalAutocompleteCoordinator {
    private var sessions: [
        TerminalSurfaceID: TerminalAutocompleteSession
    ] = [:]
    private var presentationTasks: [
        TerminalSurfaceID: Task<Void, Never>
    ] = [:]

    private let isEnabled: () -> Bool
    private let surface: (TerminalSurfaceID) -> GhosttySurfaceView?
    private let activeSurfaceIDs: () -> [TerminalSurfaceID]

    init(
        isEnabled: @escaping () -> Bool,
        surface: @escaping (TerminalSurfaceID) -> GhosttySurfaceView?,
        activeSurfaceIDs: @escaping () -> [TerminalSurfaceID]
    ) {
        self.isEnabled = isEnabled
        self.surface = surface
        self.activeSurfaceIDs = activeSurfaceIDs
    }

    func bind(surfaceID: TerminalSurfaceID) {
        sessions[surfaceID] = TerminalAutocompleteSession()
    }

    /// Returns whether the key was consumed (an autocomplete suggestion
    /// was inserted) rather than passed through to the terminal.
    func handleKey(
        _ event: NSEvent,
        for surfaceID: TerminalSurfaceID
    ) -> Bool {
        guard isEnabled(),
              let surface = surface(surfaceID),
              var session = sessions[surfaceID],
              let input = TerminalAutocompleteEventMapper.input(
                  for: event,
                  hasMarkedText: surface.hasMarkedText()
              )
        else { return false }

        presentationTasks.removeValue(forKey: surfaceID)?.cancel()
        let action = session.handle(input)
        sessions[surfaceID] = session

        switch action {
        case .hide:
            surface.setAutocompleteSuggestion(nil)
            return false
        case .show:
            schedulePresentation(
                action,
                for: surfaceID,
                delay: .milliseconds(10)
            )
            return false
        case let .insert(text):
            surface.setAutocompleteSuggestion(nil)
            surface.sendText(text)
            return true
        }
    }

    func handleCommandFinished(
        exitCode: Int?,
        surfaceID: TerminalSurfaceID
    ) {
        guard isEnabled(),
              let surface = surface(surfaceID),
              var session = sessions[surfaceID]
        else { return }

        let action = session.commandFinished(
            exitCode: exitCode,
            reportedCommand: surface.terminalTitle
        )
        sessions[surfaceID] = session
        schedulePresentation(
            action,
            for: surfaceID,
            delay: .milliseconds(60)
        )
    }

    private func schedulePresentation(
        _ action: TerminalAutocompleteAction,
        for surfaceID: TerminalSurfaceID,
        delay: Duration
    ) {
        presentationTasks.removeValue(forKey: surfaceID)?.cancel()
        if action == .hide {
            surface(surfaceID)?.setAutocompleteSuggestion(nil)
            return
        }

        presentationTasks[surfaceID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            presentationTasks.removeValue(forKey: surfaceID)
            guard isEnabled(), let surface = surface(surfaceID) else {
                return
            }
            switch action {
            case let .show(suggestion):
                surface.setAutocompleteSuggestion(suggestion.displayText)
            case .hide, .insert:
                surface.setAutocompleteSuggestion(nil)
            }
        }
    }

    func clearSuggestions() {
        for task in presentationTasks.values {
            task.cancel()
        }
        presentationTasks.removeAll()
        let surfaceIDs = activeSurfaceIDs()
        for surfaceID in surfaceIDs {
            surface(surfaceID)?.setAutocompleteSuggestion(nil)
        }
        sessions = Dictionary(
            uniqueKeysWithValues: surfaceIDs.map {
                ($0, TerminalAutocompleteSession())
            }
        )
    }

    func removeSession(for surfaceID: TerminalSurfaceID) {
        presentationTasks.removeValue(forKey: surfaceID)?.cancel()
        sessions.removeValue(forKey: surfaceID)
    }
}
