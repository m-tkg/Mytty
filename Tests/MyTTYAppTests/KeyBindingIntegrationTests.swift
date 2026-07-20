import AppKit
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Key binding integration", .serialized)
struct KeyBindingIntegrationTests {
    @Test("builds the application menu from configured key bindings")
    @MainActor
    func applicationMenu() throws {
        var bindings = MyTTYCommand.defaultKeyBindings
        bindings[.newTab] = MyTTYKeyBinding(
            key: "x",
            modifiers: [.control]
        )
        bindings[.splitLeft] = MyTTYKeyBinding(
            key: "h",
            modifiers: [.command]
        )
        bindings.removeValue(forKey: .settings)

        let menu = AppDelegate().makeMainMenu(keyBindings: bindings)
        let application = try #require(menu.items.first)
        let newTab = try #require(menu.item(titled: "New Tab"))
        let openHTML = try #require(menu.item(titled: "Open HTML File..."))
        let renameTab = try #require(menu.item(titled: "Rename Tab"))
        let toggleTabPanel = try #require(
            menu.item(titled: "Toggle Tab Panels")
        )
        let splitLeft = try #require(menu.item(titled: "Split Left"))
        let equalizePanes = try #require(
            menu.item(titled: "Equalize Panes")
        )
        let togglePaneZoom = try #require(
            menu.item(titled: "Toggle Pane Zoom")
        )
        let findInPane = try #require(menu.item(titled: "Find in Pane"))
        let showPaneList = try #require(
            menu.item(titled: "Show All Panes")
        )
        let toggleRecording = try #require(
            menu.item(titled: "Start/Stop Recording")
        )
        let settings = try #require(menu.item(titled: "Settings..."))
        let about = try #require(menu.item(titled: "About Mytty"))

        #expect(application.title == ApplicationIdentity.displayName)
        #expect(application.submenu?.title == ApplicationIdentity.displayName)
        #expect(about.keyEquivalent.isEmpty)
        #expect(newTab.keyEquivalent == "x")
        #expect(openHTML.keyEquivalent == "o")
        #expect(renameTab.keyEquivalent == "r")
        #expect(toggleTabPanel.keyEquivalent == "b")
        #expect(
            newTab.keyEquivalentModifierMask
                == NSEvent.ModifierFlags.control
        )
        #expect(splitLeft.keyEquivalent == "h")
        #expect(
            splitLeft.keyEquivalentModifierMask
                == NSEvent.ModifierFlags.command
        )
        #expect(settings.keyEquivalent.isEmpty)
        #expect(settings.keyEquivalentModifierMask.isEmpty)
        #expect(equalizePanes.keyEquivalent == "=")
        #expect(
            equalizePanes.keyEquivalentModifierMask
                == [.control, .command]
        )
        #expect(togglePaneZoom.keyEquivalent == "\r")
        #expect(
            togglePaneZoom.keyEquivalentModifierMask
                == [.control, .command]
        )
        #expect(findInPane.keyEquivalent == "f")
        #expect(findInPane.keyEquivalentModifierMask == .control)
        #expect(showPaneList.keyEquivalent == "p")
        #expect(
            showPaneList.keyEquivalentModifierMask == [.control, .command]
        )
        #expect(toggleRecording.keyEquivalent == "g")
        #expect(
            toggleRecording.keyEquivalentModifierMask == [.shift, .command]
        )
    }

    @Test("consumes configured punctuation shortcuts before terminal input")
    @MainActor
    func consumesPunctuationShortcut() throws {
        let binding = try #require(
            MyTTYKeyBinding(
                serialized: "control+shift+command+|"
            )
        )
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift, .command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "|",
            charactersIgnoringModifiers: "|",
            isARepeat: false,
            keyCode: 42
        ))
        var invokedCommands: [MyTTYCommand] = []
        var scheduledAction: (@MainActor () -> Void)?

        let routedEvent = ApplicationShortcutRouter.route(
            event,
            bindings: [.splitRight: binding],
            schedule: { scheduledAction = $0 },
            invoke: { command in
                invokedCommands.append(command)
                return true
            }
        )

        #expect(routedEvent == nil)
        #expect(invokedCommands.isEmpty)

        scheduledAction?()

        #expect(invokedCommands == [.splitRight])
    }

    @Test("observes a pressed key after routing its application shortcut")
    @MainActor
    func observesRoutedShortcut() throws {
        let binding = try #require(
            MyTTYKeyBinding(serialized: "command+d")
        )
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))
        var scheduledActions: [(@MainActor () -> Void)] = []
        var timeline: [String] = []

        let routedEvent = ApplicationShortcutRouter.routeAndObserve(
            event,
            bindings: [.splitRight: binding],
            schedule: { scheduledActions.append($0) },
            observe: { observedEvent in
                timeline.append(TerminalKeyLabel.text(for: observedEvent) ?? "")
            },
            invoke: { command in
                timeline.append(command.rawValue)
                return true
            }
        )

        #expect(routedEvent == nil)
        #expect(scheduledActions.count == 2)

        scheduledActions.forEach { $0() }

        #expect(timeline == ["split-right", "⌘D"])
    }

    @Test("Delete clears a key binding while recording")
    @MainActor
    func deleteClearsBinding() throws {
        var changes: [MyTTYKeyBinding?] = []
        let recorder = KeyBindingRecorderButton(
            binding: MyTTYCommand.defaultKeyBindings[.newTab],
            onChange: { changes.append($0) }
        )
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{7F}",
            charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false,
            keyCode: 51
        ))

        recorder.beginRecording()
        recorder.keyDown(with: event)

        #expect(changes.count == 1)
        #expect(changes[0] == nil)
        #expect(!recorder.isRecording)
    }

    @Test("recording captures an existing application shortcut first")
    @MainActor
    func capturesExistingShortcut() throws {
        var changes: [MyTTYKeyBinding?] = []
        let recorder = KeyBindingRecorderButton(
            binding: nil,
            onChange: { changes.append($0) }
        )
        let target = MenuShortcutTarget()
        let menu = NSMenu()
        let rootItem = NSMenuItem()
        let submenu = NSMenu()
        let menuItem = submenu.addItem(
            withTitle: "Existing Shortcut",
            action: #selector(MenuShortcutTarget.invoke(_:)),
            keyEquivalent: "w"
        )
        menuItem.target = target
        rootItem.submenu = submenu
        menu.addItem(rootItem)
        let previousMenu = NSApplication.shared.mainMenu
        NSApplication.shared.mainMenu = menu
        defer { NSApplication.shared.mainMenu = previousMenu }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        recorder.beginRecording()
        NSApplication.shared.sendEvent(event)

        #expect(
            changes == [
                MyTTYKeyBinding(key: "w", modifiers: [.command]),
            ]
        )
        #expect(target.invocationCount == 0)
    }

    @Test("browser panes route application shortcuts before WebKit")
    @MainActor
    func browserApplicationShortcut() throws {
        let target = MenuShortcutTarget()
        let menu = NSMenu()
        let rootItem = NSMenuItem()
        let submenu = NSMenu()
        let menuItem = submenu.addItem(
            withTitle: "Split Right",
            action: #selector(MenuShortcutTarget.invoke(_:)),
            keyEquivalent: "d"
        )
        menuItem.keyEquivalentModifierMask = .command
        menuItem.target = target
        rootItem.submenu = submenu
        menu.addItem(rootItem)
        let previousMenu = NSApplication.shared.mainMenu
        NSApplication.shared.mainMenu = menu
        defer { NSApplication.shared.mainMenu = previousMenu }
        let browser = BrowserPaneView(url: URL(string: "about:blank")!)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))

        #expect(browser.performKeyEquivalent(with: event))
        #expect(target.invocationCount == 1)
    }

    @Test("browser web content routes shortcuts through the application menu")
    @MainActor
    func browserWebContentShortcut() throws {
        let target = MenuShortcutTarget()
        let menu = NSMenu()
        let rootItem = NSMenuItem()
        let submenu = NSMenu()
        let menuItem = submenu.addItem(
            withTitle: "Split Right",
            action: #selector(MenuShortcutTarget.invoke(_:)),
            keyEquivalent: "d"
        )
        menuItem.keyEquivalentModifierMask = .command
        menuItem.target = target
        rootItem.submenu = submenu
        menu.addItem(rootItem)
        let previousMenu = NSApplication.shared.mainMenu
        NSApplication.shared.mainMenu = menu
        defer { NSApplication.shared.mainMenu = previousMenu }

        let browser = BrowserPaneView(url: URL(string: "about:blank")!)
        let webContent = NSView()
        browser.addSubview(webContent)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))

        #expect(
            browser.routeApplicationShortcut(
                event,
                firstResponder: webContent
            )
        )
        #expect(target.invocationCount == 1)
    }
}

@MainActor
private final class MenuShortcutTarget: NSObject {
    private(set) var invocationCount = 0

    @objc func invoke(_ sender: Any?) {
        invocationCount += 1
    }
}

private extension NSMenu {
    func item(titled title: String) -> NSMenuItem? {
        for item in items {
            if item.title == title {
                return item
            }
            if let match = item.submenu?.item(titled: title) {
                return match
            }
        }
        return nil
    }
}
