import Combine
import Foundation
import GhosttyAdapter
import MyTTYCore

/// Owns the pane-input-schedule editing/delivery flow: the `$schedules`
/// subscription, the new/edit/delete dialog plumbing, and delivering a
/// due schedule's text (plus its delayed Enter) into the target surface.
/// Extracted from `TerminalWindowController.observePaneInputSchedules` /
/// `newScheduledInput` / `editScheduledInput` / `presentScheduledInputEditor`
/// / `deleteScheduledInput` / `deliverScheduledInput` /
/// `removeScheduledInputs` verbatim — including the 0.1s delay before the
/// trailing Enter, which lets TUI agents distinguish typed text from a
/// paste.
///
/// `PaneInputScheduler` itself is owned by the app (constructed alongside
/// `TerminalWindowController`) and handed in directly, matching how other
/// coordinators in this file take their backing store as a plain
/// constructor argument. `TerminalWindowController` supplies live surface
/// lookups via a closure (`surfaces` is controller-private) and pushes
/// localizer updates via `updateLocalizer` when the app language changes,
/// since presenting the editor dialog needs a live `MyTTYLocalizer` and a
/// closure snapshot taken once at construction would go stale.
///
/// `updateScheduledInputStatus` (which pushes schedules into
/// `TerminalStatusBarModel`) stays on the controller: it reaches into
/// `WindowSession` and `statusBarModel`, both controller-private. This
/// coordinator instead reports schedule changes via `onSchedulesChanged`,
/// same shape as the other coordinators' `onXChanged` callbacks.
@MainActor
final class ScheduledInputCoordinator {
    private let scheduler: PaneInputScheduler
    private var schedulesObserver: AnyCancellable?
    private var localizer: MyTTYLocalizer

    private let surface: (TerminalSurfaceID) -> GhosttySurfaceView?
    private let presentError: (Error) -> Void
    private let onSchedulesChanged: ([PaneInputSchedule]) -> Void

    init(
        scheduler: PaneInputScheduler,
        localizer: MyTTYLocalizer,
        surface: @escaping (TerminalSurfaceID) -> GhosttySurfaceView?,
        presentError: @escaping (Error) -> Void,
        onSchedulesChanged: @escaping ([PaneInputSchedule]) -> Void
    ) {
        self.scheduler = scheduler
        self.localizer = localizer
        self.surface = surface
        self.presentError = presentError
        self.onSchedulesChanged = onSchedulesChanged
    }

    func startObserving() {
        schedulesObserver = scheduler.$schedules.sink { [weak self] schedules in
            self?.onSchedulesChanged(schedules)
        }
    }

    func updateLocalizer(_ localizer: MyTTYLocalizer) {
        self.localizer = localizer
    }

    var schedules: [PaneInputSchedule] { scheduler.schedules }

    func newScheduledInput(focusedSurfaceID: TerminalSurfaceID?) {
        guard let focusedID = focusedSurfaceID,
              surface(focusedID) != nil
        else { return }
        presentEditor(draft: PaneInputScheduleDraft(surfaceID: focusedID))
    }

    func editScheduledInput(_ schedule: PaneInputSchedule) {
        guard surface(schedule.surfaceID) != nil else { return }
        presentEditor(draft: PaneInputScheduleDraft(schedule: schedule))
    }

    private func presentEditor(draft: PaneInputScheduleDraft) {
        guard let schedule = PaneInputScheduleDialog.run(
            draft: draft,
            localizer: localizer
        ) else { return }
        do {
            try scheduler.save(schedule)
        } catch {
            presentError(error)
        }
    }

    func deleteScheduledInput(_ schedule: PaneInputSchedule) {
        do {
            try scheduler.delete(id: schedule.id)
        } catch {
            presentError(error)
        }
    }

    /// TUI agents treat an Enter arriving in the same instant as the text
    /// as part of a paste, so the newline follows after a short delay.
    static let enterDelay: TimeInterval = 0.1

    @discardableResult
    func deliverScheduledInput(_ schedule: PaneInputSchedule) -> Bool {
        guard let surfaceView = surface(schedule.surfaceID) else { return false }
        surfaceView.sendText(schedule.text)
        if schedule.appendNewline {
            let surfaceID = schedule.surfaceID
            let surfaceLookup = surface
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.enterDelay
            ) {
                surfaceLookup(surfaceID)?.sendEnter()
            }
        }
        return true
    }

    func removeScheduledInputs(for surfaceIDs: [TerminalSurfaceID]) {
        do {
            for surfaceID in surfaceIDs {
                try scheduler.deleteAll(for: surfaceID)
            }
        } catch {
            presentError(error)
        }
    }
}
