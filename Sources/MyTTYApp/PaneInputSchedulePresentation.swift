import AppKit
import MyTTYCore
import SwiftUI

struct PaneInputScheduleDraft: Equatable {
    let id: PaneInputScheduleID
    let surfaceID: TerminalSurfaceID
    var fireAt: Date
    var text: String
    var appendNewline: Bool

    init(
        surfaceID: TerminalSurfaceID,
        now: Date = Date()
    ) {
        self.id = PaneInputScheduleID()
        self.surfaceID = surfaceID
        self.fireAt = now.addingTimeInterval(60)
        self.text = ""
        self.appendNewline = true
    }

    init(schedule: PaneInputSchedule) {
        self.id = schedule.id
        self.surfaceID = schedule.surfaceID
        self.fireAt = schedule.fireAt
        self.text = schedule.text
        self.appendNewline = schedule.appendNewline
    }

    var schedule: PaneInputSchedule {
        PaneInputSchedule(
            id: id,
            surfaceID: surfaceID,
            fireAt: fireAt,
            text: text,
            appendNewline: appendNewline
        )
    }
}

enum PaneInputScheduleScope {
    static func liveSurfaceIDs(
        in sessions: [WindowSession]
    ) -> Set<TerminalSurfaceID> {
        Set(
            sessions.flatMap { session in
                session.tabs.flatMap(\.surfaceIDs)
            }
        )
    }
}

@MainActor
enum ScheduledInputMenuHierarchy {
    static func root(startingAt menu: NSMenu) -> NSMenu {
        var root = menu
        while let parent = root.supermenu {
            root = parent
        }
        return root
    }
}

@MainActor
enum PaneInputScheduleDialog {
    static func run(
        draft: PaneInputScheduleDraft,
        localizer: MyTTYLocalizer
    ) -> PaneInputSchedule? {
        let editor = PaneInputScheduleEditorView(
            draft: draft,
            localizer: localizer
        )
        let alert = ApplicationAlert.make()
        alert.messageText = localizer[.scheduledInput]
        alert.accessoryView = editor
        alert.addButton(withTitle: localizer[.save])
        alert.addButton(withTitle: localizer[.cancel])
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return editor.schedule
    }
}

@MainActor
private final class PaneInputScheduleEditorView: NSView {
    private let id: PaneInputScheduleID
    private let surfaceID: TerminalSurfaceID
    private let datePicker: NSDatePicker
    private let textField: NSTextField
    private let appendNewlineButton: NSButton

    var schedule: PaneInputSchedule {
        PaneInputSchedule(
            id: id,
            surfaceID: surfaceID,
            fireAt: datePicker.dateValue,
            text: textField.stringValue,
            appendNewline: appendNewlineButton.state == .on
        )
    }

    init(
        draft: PaneInputScheduleDraft,
        localizer: MyTTYLocalizer
    ) {
        self.id = draft.id
        self.surfaceID = draft.surfaceID
        self.datePicker = NSDatePicker()
        self.textField = NSTextField(string: draft.text)
        self.appendNewlineButton = NSButton(
            checkboxWithTitle: localizer[.appendNewline],
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 104))

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        datePicker.dateValue = draft.fireAt
        datePicker.minDate = Date()
        appendNewlineButton.state = draft.appendNewline ? .on : .off

        let grid = NSGridView(views: [
            [label(localizer[.dateAndTime]), datePicker],
            [label(localizer[.inputText]), textField],
            [NSView(), appendNewlineButton],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        addSubview(grid)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 270),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.alignment = .right
        return field
    }
}

@MainActor
struct ScheduledInputMenuButton: NSViewRepresentable {
    let schedules: [PaneInputSchedule]
    let canCreate: Bool
    let localizer: MyTTYLocalizer
    let onNew: () -> Void
    let onEdit: (PaneInputSchedule) -> Void
    let onDelete: (PaneInputSchedule) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func symbolName(hasSchedules: Bool) -> String {
        hasSchedules ? "clock.fill" : "clock"
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.showMenu(_:))
        )
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = localizer[.scheduledInput]
        button.setAccessibilityLabel(localizer[.scheduledInput])
        updateIndicator(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.toolTip = localizer[.scheduledInput]
        button.setAccessibilityLabel(localizer[.scheduledInput])
        updateIndicator(button)
    }

    private func updateIndicator(_ button: NSButton) {
        let hasSchedules = !schedules.isEmpty
        button.image = NSImage(
            systemSymbolName: Self.symbolName(hasSchedules: hasSchedules),
            accessibilityDescription: nil
        ) ?? NSImage()
        button.contentTintColor = hasSchedules
            ? .controlAccentColor
            : .secondaryLabelColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScheduledInputMenuButton

        init(parent: ScheduledInputMenuButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu(title: parent.localizer[.scheduledInput])
            menu.autoenablesItems = false
            let newItem = NSMenuItem(
                title: parent.localizer[.newScheduledInput],
                action: #selector(createSchedule(_:)),
                keyEquivalent: ""
            )
            newItem.target = self
            newItem.isEnabled = parent.canCreate
            menu.addItem(newItem)

            if !parent.schedules.isEmpty {
                menu.addItem(.separator())
                let scheduledItem = NSMenuItem(
                    title: parent.localizer[.scheduled],
                    action: nil,
                    keyEquivalent: ""
                )
                scheduledItem.submenu = makeScheduledMenu()
                menu.addItem(scheduledItem)
            }

            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 3),
                in: sender
            )
        }

        @objc private func createSchedule(_ sender: NSMenuItem) {
            parent.onNew()
        }

        func makeScheduledMenu() -> NSMenu {
            let menu = NSMenu(title: parent.localizer[.scheduled])
            menu.autoenablesItems = false
            for schedule in parent.schedules {
                let item = NSMenuItem()
                item.view = ScheduledInputMenuRow(
                    title: formattedDate(schedule.fireAt),
                    message: schedule.text,
                    onEdit: { [parent] in parent.onEdit(schedule) },
                    onDelete: { [parent] in parent.onDelete(schedule) }
                )
                item.isEnabled = true
                menu.addItem(item)
            }
            return menu
        }

        private func formattedDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: parent.localizer.language == .japanese
                    ? "ja_JP"
                    : "en_US"
            )
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
    }
}

@MainActor
private final class ScheduledInputMenuRow: NSView {
    private let onEdit: () -> Void
    private let onDelete: () -> Void
    private var deferredAction: (() -> Void)?

    init(
        title: String,
        message: String,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.onEdit = onEdit
        self.onDelete = onDelete
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 28))

        let editButton = NSButton(title: title, target: self, action: #selector(edit))
        editButton.isBordered = false
        editButton.alignment = .left
        editButton.lineBreakMode = .byTruncatingTail
        editButton.contentTintColor = .labelColor
        editButton.toolTip = message
        editButton.translatesAutoresizingMaskIntoConstraints = false

        let deleteButton = NSButton(
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
                ?? NSImage(),
            target: self,
            action: #selector(deleteSchedule)
        )
        deleteButton.isBordered = false
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setAccessibilityLabel("Delete")
        toolTip = message

        addSubview(editButton)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            editButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            editButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func edit() {
        performAfterClosingMenu(onEdit)
    }

    @objc private func deleteSchedule() {
        performAfterClosingMenu(onDelete)
    }

    private func performAfterClosingMenu(
        _ action: @escaping () -> Void
    ) {
        if let menu = enclosingMenuItem?.menu {
            ScheduledInputMenuHierarchy.root(startingAt: menu)
                .cancelTracking()
        }
        deferredAction = action
        let timer = Timer(
            timeInterval: 0,
            target: self,
            selector: #selector(invokeDeferredAction(_:)),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .default)
    }

    @objc private func invokeDeferredAction(_ timer: Timer) {
        let action = deferredAction
        deferredAction = nil
        action?()
    }
}
