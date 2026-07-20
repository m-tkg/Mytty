import AppKit
import MyTTYCore

@MainActor
final class ApplicationShortcutRouter {
    private var bindings: [MyTTYCommand: MyTTYKeyBinding]
    private let onKeyPressed: (NSEvent) -> Void
    private var eventMonitor: Any?

    init(
        bindings: [MyTTYCommand: MyTTYKeyBinding],
        onKeyPressed: @escaping (NSEvent) -> Void = { _ in }
    ) {
        self.bindings = bindings
        self.onKeyPressed = onKeyPressed
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self else { return event }
            guard !(NSApplication.shared.keyWindow?.firstResponder
                is KeyBindingRecorderButton)
            else { return event }
            return Self.routeAndObserve(
                event,
                bindings: self.bindings,
                schedule: { action in
                    DispatchQueue.main.async { action() }
                },
                observe: self.onKeyPressed,
                invoke: self.invoke
            )
        }
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    func update(bindings: [MyTTYCommand: MyTTYKeyBinding]) {
        self.bindings = bindings
    }

    static func route(
        _ event: NSEvent,
        bindings: [MyTTYCommand: MyTTYKeyBinding],
        schedule: (@escaping @MainActor () -> Void) -> Void,
        invoke: @escaping (MyTTYCommand) -> Bool
    ) -> NSEvent? {
        guard event.type == .keyDown,
              let binding = MyTTYKeyBinding(event: event),
              let command = MyTTYCommand.allCases.first(where: {
                  bindings[$0] == binding
              })
        else { return event }
        schedule { _ = invoke(command) }
        return nil
    }

    static func routeAndObserve(
        _ event: NSEvent,
        bindings: [MyTTYCommand: MyTTYKeyBinding],
        schedule: (@escaping @MainActor () -> Void) -> Void,
        observe: @escaping (NSEvent) -> Void,
        invoke: @escaping (MyTTYCommand) -> Bool
    ) -> NSEvent? {
        let routed = route(
            event,
            bindings: bindings,
            schedule: schedule,
            invoke: invoke
        )
        schedule { observe(event) }
        return routed
    }

    private func invoke(_ command: MyTTYCommand) -> Bool {
        guard let item = NSApplication.shared.mainMenu?.item(
            for: command
        ), item.isEnabled, let action = item.action
        else { return false }
        return NSApplication.shared.sendAction(
            action,
            to: item.target,
            from: item
        )
    }
}

private extension NSMenu {
    func item(for command: MyTTYCommand) -> NSMenuItem? {
        for item in items {
            if item.representedObject as? String == command.rawValue {
                return item
            }
            if let match = item.submenu?.item(for: command) {
                return match
            }
        }
        return nil
    }
}
