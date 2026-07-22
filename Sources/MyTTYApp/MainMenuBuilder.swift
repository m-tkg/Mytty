import AppKit
import MyTTYCore

/// Builds the application's main menu bar. Actions are wired with explicit
/// selectors against `AppDelegate` and dispatched through `target`, so
/// behavior (including responder-chain routing) matches what `AppDelegate`
/// did when it built the menu itself.
@MainActor
enum MainMenuBuilder {
    static func makeMainMenu(
        keyBindings: [MyTTYCommand: MyTTYKeyBinding]
            = MyTTYCommand.defaultKeyBindings,
        localizer: MyTTYLocalizer = MyTTYLocalizer(language: .english),
        target: AppDelegate
    ) -> NSMenu {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem(
            title: ApplicationIdentity.displayName,
            action: nil,
            keyEquivalent: ""
        )
        let applicationMenu = NSMenu(title: ApplicationIdentity.displayName)
        let aboutItem = applicationMenu.addItem(
            withTitle: localizer[.aboutMyTTY],
            action: #selector(AppDelegate.showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = target
        applicationMenu.addItem(.separator())
        addCommandItem(
            to: applicationMenu,
            title: localizer[.settings] + "...",
            action: #selector(AppDelegate.showSettings(_:)),
            command: .settings,
            keyBindings: keyBindings,
            target: target
        )
        applicationMenu.addItem(.separator())
        let quitItem = addCommandItem(
            to: applicationMenu,
            title: localizer.commandTitle(.quit),
            action: #selector(NSApplication.terminate(_:)),
            command: .quit,
            keyBindings: keyBindings,
            target: target
        )
        quitItem.target = NSApplication.shared
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: localizer[.file])
        addCommandItem(
            to: fileMenu,
            title: localizer.commandTitle(.openHTML) + "...",
            action: #selector(AppDelegate.openHTML(_:)),
            command: .openHTML,
            keyBindings: keyBindings,
            target: target
        )
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // The one-liner composer needs Foundation Models (macOS 26+); the
        // Edit menu itself and the input composer are available on every
        // supported system, so only that item is gated below.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: localizer[.edit])
        // Standard first-responder edit items. Nil targets keep them
        // enabled only where the focused view implements the action
        // (e.g. the composer panels' text fields), so Cmd+C/V still reach
        // the terminal surface unchanged when it is focused.
        editMenu.addItem(
            withTitle: localizer[.cut],
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: localizer[.copy],
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: localizer[.paste],
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: localizer[.selectAll],
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(.separator())
        addCommandItem(
            to: editMenu,
            title: localizer.commandTitle(.composeInput),
            action: #selector(AppDelegate.composeInput(_:)),
            command: .composeInput,
            keyBindings: keyBindings,
            target: target
        )
        if #available(macOS 26, *) {
            addCommandItem(
                to: editMenu,
                title: localizer.commandTitle(.composeOneLiner),
                action: #selector(AppDelegate.composeOneLiner(_:)),
                command: .composeOneLiner,
                keyBindings: keyBindings,
                target: target
            )
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: localizer[.window])
        addCommandItem(
            to: windowMenu,
            title: localizer.commandTitle(.newWindow),
            action: #selector(AppDelegate.newWindow(_:)),
            command: .newWindow,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: windowMenu,
            title: localizer.commandTitle(.nextWindow),
            action: #selector(AppDelegate.nextWindow(_:)),
            command: .nextWindow,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: windowMenu,
            title: localizer.commandTitle(.previousWindow),
            action: #selector(AppDelegate.previousWindow(_:)),
            command: .previousWindow,
            keyBindings: keyBindings,
            target: target
        )
        windowMenu.addItem(.separator())
        addCommandItem(
            to: windowMenu,
            title: localizer.commandTitle(.reopenClosed),
            action: #selector(AppDelegate.reopenClosed(_:)),
            command: .reopenClosed,
            keyBindings: keyBindings,
            target: target
        )
        let recentlyClosedItem = NSMenuItem(
            title: localizer[.recentlyClosedItems],
            action: nil,
            keyEquivalent: ""
        )
        let recentlyClosedMenu = NSMenu(title: localizer[.recentlyClosedItems])
        recentlyClosedMenu.delegate = target
        recentlyClosedItem.submenu = recentlyClosedMenu
        windowMenu.addItem(recentlyClosedItem)
        windowMenu.addItem(.separator())

        let tabsItem = NSMenuItem(
            title: localizer[.tabs],
            action: nil,
            keyEquivalent: ""
        )
        let tabsMenu = NSMenu(title: localizer[.tabs])
        addCommandItem(
            to: tabsMenu,
            title: localizer.commandTitle(.newTab),
            action: #selector(AppDelegate.newTab(_:)),
            command: .newTab,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: tabsMenu,
            title: localizer.commandTitle(.renameTab),
            action: #selector(AppDelegate.renameTab(_:)),
            command: .renameTab,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: tabsMenu,
            title: localizer.commandTitle(.closeTab),
            action: #selector(AppDelegate.closeTab(_:)),
            command: .closeTab,
            keyBindings: keyBindings,
            target: target
        )
        tabsMenu.addItem(.separator())
        addCommandItem(
            to: tabsMenu,
            title: localizer.commandTitle(.nextTab),
            action: #selector(AppDelegate.nextTab(_:)),
            command: .nextTab,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: tabsMenu,
            title: localizer.commandTitle(.previousTab),
            action: #selector(AppDelegate.previousTab(_:)),
            command: .previousTab,
            keyBindings: keyBindings,
            target: target
        )
        tabsMenu.addItem(.separator())
        for (index, command) in MyTTYCommand.numberedTabCommands.enumerated() {
            let item = addCommandItem(
                to: tabsMenu,
                title: localizer.commandTitle(command),
                action: #selector(AppDelegate.selectNumberedTab(_:)),
                command: command,
                keyBindings: keyBindings,
                target: target
            )
            item.tag = index + 1
        }
        tabsItem.submenu = tabsMenu
        windowMenu.addItem(tabsItem)

        let paneItem = NSMenuItem(
            title: localizer[.pane],
            action: nil,
            keyEquivalent: ""
        )
        let paneMenu = NSMenu(title: localizer[.pane])
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.showPaneList),
            action: #selector(AppDelegate.showPaneList(_:)),
            command: .showPaneList,
            keyBindings: keyBindings,
            target: target
        )
        paneMenu.addItem(.separator())
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.splitLeft),
            action: #selector(AppDelegate.splitLeft(_:)),
            command: .splitLeft,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.splitRight),
            action: #selector(AppDelegate.splitRight(_:)),
            command: .splitRight,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.splitUp),
            action: #selector(AppDelegate.splitUp(_:)),
            command: .splitUp,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.splitDown),
            action: #selector(AppDelegate.splitDown(_:)),
            command: .splitDown,
            keyBindings: keyBindings,
            target: target
        )
        paneMenu.addItem(.separator())
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.equalizePanes),
            action: #selector(AppDelegate.equalizePanes(_:)),
            command: .equalizePanes,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.togglePaneZoom),
            action: #selector(AppDelegate.togglePaneZoom(_:)),
            command: .togglePaneZoom,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.swapPanes),
            action: #selector(AppDelegate.swapPanes(_:)),
            command: .swapPanes,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.findInPane),
            action: #selector(AppDelegate.findInPane(_:)),
            command: .findInPane,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.reloadBrowser),
            action: #selector(AppDelegate.reloadBrowser(_:)),
            command: .reloadBrowser,
            keyBindings: keyBindings,
            target: target
        )
        // On-device pane explanation needs Foundation Models (macOS 26+);
        // the menu item must not appear on older systems.
        if #available(macOS 26, *) {
            addCommandItem(
                to: paneMenu,
                title: localizer.commandTitle(.explainPane),
                action: #selector(AppDelegate.explainPane(_:)),
                command: .explainPane,
                keyBindings: keyBindings,
                target: target
            )
            addCommandItem(
                to: paneMenu,
                title: localizer.commandTitle(.summarizeLastCommand),
                action: #selector(AppDelegate.summarizeLastCommand(_:)),
                command: .summarizeLastCommand,
                keyBindings: keyBindings,
                target: target
            )
        }
        paneMenu.addItem(.separator())
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.focusLeft),
            action: #selector(AppDelegate.focusPaneLeft(_:)),
            command: .focusLeft,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.focusRight),
            action: #selector(AppDelegate.focusPaneRight(_:)),
            command: .focusRight,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.focusUp),
            action: #selector(AppDelegate.focusPaneUp(_:)),
            command: .focusUp,
            keyBindings: keyBindings,
            target: target
        )
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.focusDown),
            action: #selector(AppDelegate.focusPaneDown(_:)),
            command: .focusDown,
            keyBindings: keyBindings,
            target: target
        )
        paneMenu.addItem(.separator())
        addCommandItem(
            to: paneMenu,
            title: localizer.commandTitle(.closePane),
            action: #selector(AppDelegate.closePane(_:)),
            command: .closePane,
            keyBindings: keyBindings,
            target: target
        )
        paneItem.submenu = paneMenu
        windowMenu.addItem(paneItem)

        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: localizer[.minimizeWindow],
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: localizer[.zoomWindow],
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        let bringAllItem = windowMenu.addItem(
            withTitle: localizer[.bringAllToFront],
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        bringAllItem.target = NSApplication.shared
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApplication.shared.windowsMenu = windowMenu

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: localizer[.view])
        addCommandItem(
            to: viewMenu,
            title: localizer.commandTitle(.commandPalette) + "...",
            action: #selector(AppDelegate.showCommandPalette(_:)),
            command: .commandPalette,
            keyBindings: keyBindings,
            target: target
        )
        viewMenu.addItem(.separator())
        addCommandItem(
            to: viewMenu,
            title: localizer.commandTitle(.toggleTabPanel),
            action: #selector(AppDelegate.toggleTabPanels(_:)),
            command: .toggleTabPanel,
            keyBindings: keyBindings,
            target: target
        )
        let attentionItem = viewMenu.addItem(
            withTitle: localizer[.toggleAttention],
            action: #selector(AppDelegate.toggleAttention(_:)),
            keyEquivalent: ""
        )
        attentionItem.target = target
        viewMenu.addItem(.separator())
        addCommandItem(
            to: viewMenu,
            title: localizer.commandTitle(.toggleRecording),
            action: #selector(AppDelegate.toggleRecording(_:)),
            command: .toggleRecording,
            keyBindings: keyBindings,
            target: target
        )
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        return mainMenu
    }

    @discardableResult
    private static func addCommandItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        command: MyTTYCommand,
        keyBindings: [MyTTYCommand: MyTTYKeyBinding],
        target: AnyObject
    ) -> NSMenuItem {
        let item = menu.addItem(
            withTitle: title,
            action: action,
            keyEquivalent: keyBindings[command]?.appKitKeyEquivalent ?? ""
        )
        item.keyEquivalentModifierMask = keyBindings[command]?.appKitModifierMask
            ?? []
        item.target = target
        item.representedObject = command.rawValue
        return item
    }
}
