import AppKit
import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Pane input schedule presentation")
struct PaneInputSchedulePresentationTests {
    @Test("distinguishes a scheduled pane with a filled clock")
    @MainActor
    func scheduledInputIndicator() {
        #expect(
            ScheduledInputMenuButton.symbolName(hasSchedules: false)
                == "clock"
        )
        #expect(
            ScheduledInputMenuButton.symbolName(hasSchedules: true)
                == "clock.fill"
        )
    }

    @Test("keeps schedule rows enabled and exposes the sent message")
    @MainActor
    func scheduledInputMenuRows() throws {
        let schedule = PaneInputSchedule(
            surfaceID: TerminalSurfaceID(),
            fireAt: Date(timeIntervalSince1970: 100),
            text: "git status --short",
            appendNewline: true
        )
        let button = ScheduledInputMenuButton(
            schedules: [schedule],
            canCreate: true,
            localizer: MyTTYLocalizer(language: .english),
            onNew: {},
            onEdit: { _ in },
            onDelete: { _ in }
        )

        let menu = button.makeCoordinator().makeScheduledMenu()
        let item = try #require(menu.items.first)

        #expect(!menu.autoenablesItems)
        #expect(item.isEnabled)
        #expect(item.view?.toolTip == "git status --short")
    }

    @Test("creates a new draft for the selected pane one minute ahead")
    func newDraft() {
        let now = Date(timeIntervalSince1970: 100)
        let surfaceID = TerminalSurfaceID()

        let draft = PaneInputScheduleDraft(
            surfaceID: surfaceID,
            now: now
        )

        #expect(draft.surfaceID == surfaceID)
        #expect(draft.fireAt == Date(timeIntervalSince1970: 160))
        #expect(draft.text.isEmpty)
        #expect(draft.appendNewline)
    }

    @Test("round trips an existing schedule while preserving its identity")
    func existingDraft() {
        let original = PaneInputSchedule(
            surfaceID: TerminalSurfaceID(),
            fireAt: Date(timeIntervalSince1970: 200),
            text: "echo first",
            appendNewline: false
        )
        var draft = PaneInputScheduleDraft(schedule: original)

        draft.text = "echo updated"

        #expect(draft.schedule.id == original.id)
        #expect(draft.schedule.surfaceID == original.surfaceID)
        #expect(draft.schedule.fireAt == original.fireAt)
        #expect(draft.schedule.text == "echo updated")
        #expect(!draft.schedule.appendNewline)
    }

    @Test("restores schedules only for terminal panes in live windows")
    func liveSurfaceScope() {
        let terminal = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let browser = BrowserPaneState(
            url: URL(string: "https://example.com")!
        )
        let terminalTab = TabSession(initialSurface: terminal)
        let browserTab = TabSession(initialBrowser: browser)
        let window = WindowSession(
            frame: WindowFrame(x: 0, y: 0, width: 900, height: 600),
            tabs: [terminalTab, browserTab],
            selectedTabID: terminalTab.id
        )

        #expect(
            PaneInputScheduleScope.liveSurfaceIDs(in: [window])
                == [terminal.id]
        )
    }

    @Test("finds the root menu before invoking a submenu action")
    @MainActor
    func rootScheduleMenu() {
        let root = NSMenu(title: "Root")
        let scheduledItem = NSMenuItem(
            title: "Scheduled",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: "Scheduled")
        scheduledItem.submenu = submenu
        root.addItem(scheduledItem)

        #expect(
            ScheduledInputMenuHierarchy.root(startingAt: submenu) === root
        )
    }

    @Test("applies the published schedule snapshot to the active pane")
    @MainActor
    func statusBarScheduleSnapshot() {
        let focusedID = TerminalSurfaceID()
        let otherID = TerminalSurfaceID()
        let focusedSchedule = PaneInputSchedule(
            surfaceID: focusedID,
            fireAt: Date(timeIntervalSince1970: 100),
            text: "echo focused",
            appendNewline: true
        )
        let otherSchedule = PaneInputSchedule(
            surfaceID: otherID,
            fireAt: Date(timeIntervalSince1970: 200),
            text: "echo other",
            appendNewline: true
        )
        let model = TerminalStatusBarModel()

        model.updateScheduledInputs(
            [focusedSchedule, otherSchedule],
            focusedSurfaceID: focusedID,
            isTerminalPane: true
        )
        #expect(model.schedules == [focusedSchedule])
        #expect(model.content.scheduledInputCount == 1)
        #expect(model.content.canScheduleInput)

        model.updateScheduledInputs(
            [],
            focusedSurfaceID: focusedID,
            isTerminalPane: true
        )
        #expect(model.schedules.isEmpty)
        #expect(model.content.scheduledInputCount == 0)

        model.updateScheduledInputs(
            [focusedSchedule],
            focusedSurfaceID: focusedID,
            isTerminalPane: false
        )
        #expect(model.schedules.isEmpty)
        #expect(!model.content.canScheduleInput)
    }
}
