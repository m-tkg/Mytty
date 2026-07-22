import Foundation
import MyTTYCore
import MyTTYRemoteKit

/// Backs the pane-schedule remote messages (`RemoteAccessServerDelegate`'s
/// schedule methods): validates pane/schedule IDs, guards against one pane
/// hijacking another pane's schedule, and translates to/from the Mac-side
/// `PaneInputSchedule` model. Extracted out of `RemoteAccessCoordinator` so
/// it can be exercised in tests against a real `PaneInputScheduler` without
/// standing up a `WindowSessionCoordinator` and live window controllers.
@MainActor
final class RemotePaneScheduleService {
    /// Caps a scheduled input's text, mirroring the iOS paste cap
    /// (`PaneDetailView.maxPasteBytes`): a payload this large is more
    /// likely a bug or abuse than a legitimate schedule, so it is rejected
    /// outright rather than silently truncated.
    static let maximumTextBytes = 256 * 1024

    private let scheduler: PaneInputScheduler?
    private let paneExists: (TerminalSurfaceID) -> Bool
    private let onError: (Error) -> Void

    init(
        scheduler: PaneInputScheduler?,
        paneExists: @escaping (TerminalSurfaceID) -> Bool,
        onError: @escaping (Error) -> Void
    ) {
        self.scheduler = scheduler
        self.paneExists = paneExists
        self.onError = onError
    }

    /// The pane's currently scheduled inputs. Empty (never nil) for an
    /// unknown pane, a malformed pane ID, or when there is no scheduler.
    func schedules(forPaneID paneID: String) -> [RemotePaneSchedule] {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let scheduler
        else { return [] }
        return scheduler.schedules(for: surfaceID).map(Self.remoteSchedule)
    }

    /// Saves a client-generated schedule. Rejected outright (no error
    /// reported — these are all client mistakes or hostile input, not
    /// failures) when: the pane ID or schedule ID don't parse, the pane
    /// doesn't currently exist, the text exceeds `maximumTextBytes`, or the
    /// schedule ID already belongs to a *different* pane — the repository's
    /// primary key is the schedule ID alone, so without this check a client
    /// that had merely listed another pane's schedules could learn its ID
    /// and reassign/overwrite it by creating "its own" schedule with that
    /// ID. Reusing an ID already on the *same* pane is a legitimate
    /// edit/upsert and stays allowed. A past `fireAt` throws
    /// `PaneInputSchedulerError.pastDate`, silently dropped for the same
    /// reason — the reply list simply won't contain it. Any other error
    /// (e.g. the underlying SQLite write failing) is reported via
    /// `onError`.
    func create(_ schedule: RemotePaneSchedule, forPaneID paneID: String) {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let scheduleUUID = UUID(uuidString: schedule.id),
              let scheduler,
              paneExists(surfaceID),
              schedule.text.utf8.count <= Self.maximumTextBytes
        else { return }
        let id = PaneInputScheduleID(rawValue: scheduleUUID)
        if let owner = scheduler.schedules.first(where: { $0.id == id })?.surfaceID,
           owner != surfaceID {
            return
        }
        let paneInputSchedule = PaneInputSchedule(
            id: id,
            surfaceID: surfaceID,
            fireAt: schedule.fireAt,
            text: schedule.text,
            appendNewline: schedule.pressEnter
        )
        do {
            try scheduler.save(paneInputSchedule)
        } catch PaneInputSchedulerError.pastDate {
            // Dropped silently; see the doc comment above.
        } catch {
            onError(error)
        }
    }

    /// Deletes a schedule, but only if it currently belongs to this pane —
    /// otherwise one pane could delete another's schedule just by guessing
    /// or having observed its ID.
    func delete(scheduleID: String, forPaneID paneID: String) {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let scheduleUUID = UUID(uuidString: scheduleID),
              let scheduler
        else { return }
        let id = PaneInputScheduleID(rawValue: scheduleUUID)
        guard scheduler.schedules(for: surfaceID).contains(where: { $0.id == id })
        else { return }
        do {
            try scheduler.delete(id: id)
        } catch {
            onError(error)
        }
    }

    private func terminalSurfaceID(from paneID: String) -> TerminalSurfaceID? {
        guard let uuid = UUID(uuidString: paneID) else { return nil }
        return TerminalSurfaceID(rawValue: uuid)
    }

    private static func remoteSchedule(
        _ schedule: PaneInputSchedule
    ) -> RemotePaneSchedule {
        RemotePaneSchedule(
            id: schedule.id.rawValue.uuidString,
            fireAt: schedule.fireAt,
            text: schedule.text,
            pressEnter: schedule.appendNewline
        )
    }
}
