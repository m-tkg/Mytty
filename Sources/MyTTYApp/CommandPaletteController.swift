import AppKit
import MyTTYCore

/// Floating command palette: a search field over every executable main
/// menu item. ↑/↓ move the selection, Return runs the command through the
/// same action/target the menu item uses, Escape closes.
@MainActor
final class CommandPaletteController: NSObject {
    private let panel: NSPanel
    private let searchField: NSTextField
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private let emptyLabel: NSTextField
    private let localizer: MyTTYLocalizer

    private var commands: [(entry: CommandPaletteEntry, item: NSMenuItem)] = []
    private var filtered: [(entry: CommandPaletteEntry, item: NSMenuItem)] = []

    private static let width = 560.0
    private static let listHeight = 320.0
    private static let searchHeight = 40.0
    private static let rowHeight = 40.0

    init(localizer: MyTTYLocalizer) {
        self.localizer = localizer
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: Self.width,
            height: Self.listHeight + Self.searchHeight
        )
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = localizer[.commandPalette]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false

        searchField = NSTextField(string: "")
        searchField.placeholderString =
            localizer[.commandPaletteSearchPlaceholder]
        searchField.font = .systemFont(ofSize: 16)
        searchField.focusRingType = .none
        searchField.isBezeled = true
        searchField.bezelStyle = .roundedBezel
        searchField.frame = NSRect(
            x: 10,
            y: Self.listHeight + 6,
            width: Self.width - 20,
            height: 28
        )

        tableView = NSTableView()
        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("command")
        )
        column.width = Self.width - 24
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.style = .inset
        tableView.allowsEmptySelection = false

        scrollView = NSScrollView(frame: NSRect(
            x: 0,
            y: 0,
            width: Self.width,
            height: Self.listHeight
        ))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel = NSTextField(
            labelWithString: localizer[.commandPaletteNoResults]
        )
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(
            x: 0,
            y: Self.listHeight - 60,
            width: Self.width,
            height: 20
        )
        emptyLabel.isHidden = true

        super.init()

        searchField.delegate = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(runSelectedCommand(_:))

        let content = NSView(frame: contentRect)
        content.addSubview(scrollView)
        content.addSubview(searchField)
        content.addSubview(emptyLabel)
        panel.contentView = content
        panel.initialFirstResponder = searchField
    }

    /// Reloads the commands from the current main menu and presents the
    /// palette centered over the key window's screen.
    func show(excluding excludedAction: Selector?) {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        commands = CommandPaletteMenuCollector.commands(
            in: mainMenu,
            excluding: excludedAction
        )
        searchField.stringValue = ""
        applyFilter()
        if !panel.isVisible {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func close() {
        panel.close()
    }

    private func applyFilter() {
        let query = searchField.stringValue
        let entries = CommandPaletteSearch.filter(
            commands.map(\.entry),
            query: query
        )
        filtered = entries.compactMap { entry in
            commands.first { $0.entry == entry }
        }
        emptyLabel.isHidden = !filtered.isEmpty
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let row = max(
            0,
            min(filtered.count - 1, tableView.selectedRow + delta)
        )
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    @objc private func runSelectedCommand(_ sender: Any?) {
        let row = tableView.selectedRow
        guard filtered.indices.contains(row) else { return }
        let item = filtered[row].item
        close()
        // Dispatch after the panel has resigned key so responder-chain
        // actions land on the window the user was actually working in.
        DispatchQueue.main.async {
            if let action = item.action {
                NSApplication.shared.sendAction(
                    action,
                    to: item.target,
                    from: item
                )
            }
        }
    }
}

extension CommandPaletteController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            runSelectedCommand(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}

extension CommandPaletteController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let entry = filtered[row].entry

        let identifier = NSUserInterfaceItemIdentifier("commandRow")
        let cell: CommandPaletteCellView
        if let reused = tableView.makeView(
            withIdentifier: identifier,
            owner: nil
        ) as? CommandPaletteCellView {
            cell = reused
        } else {
            cell = CommandPaletteCellView()
            cell.identifier = identifier
        }
        cell.configure(with: entry)
        return cell
    }
}

/// Two-line palette row: command title with a right-aligned shortcut, and
/// the menu path underneath in secondary text.
private final class CommandPaletteCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right

        for label in [titleLabel, pathLabel, shortcutLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 4
            ),
            titleLabel.topAnchor.constraint(
                equalTo: topAnchor, constant: 4
            ),
            shortcutLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -6
            ),
            shortcutLabel.centerYAnchor.constraint(
                equalTo: titleLabel.centerYAnchor
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -8
            ),
            pathLabel.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            pathLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -6
            ),
            pathLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: 1
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func configure(with entry: CommandPaletteEntry) {
        titleLabel.stringValue = entry.title
        pathLabel.stringValue = entry.path
        shortcutLabel.stringValue = entry.shortcut
    }
}
