import AppKit
import MyTTYCore

@MainActor
final class ApplicationShortcutRouter {
    private var bindings: [MyTTYCommand: MyTTYKeyBinding]
    private let isAvailable: (MyTTYCommand) -> Bool
    private let onKeyPressed: (NSEvent) -> Void
    private let holdEligible: (MyTTYCommand) -> Bool
    private let onHold: (MyTTYCommand) -> Void
    private let holdThreshold: TimeInterval
    private var holdRecognizer = ShortcutHoldRecognizer<MyTTYCommand>()
    private var heldKeyCode: UInt16?
    private var eventMonitor: Any?
    private var resignActiveObserver: (any NSObjectProtocol)?

    init(
        bindings: [MyTTYCommand: MyTTYKeyBinding],
        isAvailable: @escaping (MyTTYCommand) -> Bool = { _ in true },
        onKeyPressed: @escaping (NSEvent) -> Void = { _ in },
        holdEligible: @escaping (MyTTYCommand) -> Bool = { _ in false },
        onHold: @escaping (MyTTYCommand) -> Void = { _ in },
        holdThreshold: TimeInterval = 0.5
    ) {
        self.bindings = bindings
        self.isAvailable = isAvailable
        self.onKeyPressed = onKeyPressed
        self.holdEligible = holdEligible
        self.onHold = onHold
        self.holdThreshold = holdThreshold
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]
        ) { [weak self] event in
            guard let self else { return event }
            guard !(NSApplication.shared.keyWindow?.firstResponder
                is KeyBindingRecorderButton)
            else { return event }
            if event.type == .keyUp {
                return self.routeKeyUp(event)
            }
            if self.routeHoldKeyDown(event) {
                return nil
            }
            return Self.routeAndObserve(
                event,
                bindings: self.bindings,
                isAvailable: self.isAvailable,
                schedule: { action in
                    DispatchQueue.main.async { action() }
                },
                observe: self.onKeyPressed,
                invoke: self.invoke
            )
        }
        // Losing active status means the matching key-up will never reach
        // the local monitor; abandon the press so the hold timer cannot
        // split behind the user's back (e.g. after Cmd+Tab away).
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holdRecognizer.cancel()
                self.heldKeyCode = nil
            }
        }
    }

    /// Consumes the release of a key whose press started a hold, so a
    /// quick tap performs the command and a hold performs its alternate.
    private func routeKeyUp(_ event: NSEvent) -> NSEvent? {
        guard holdRecognizer.isTracking,
              heldKeyCode == event.keyCode
        else { return event }
        heldKeyCode = nil
        perform(holdRecognizer.keyUp())
        return nil
    }

    /// Intercepts key-downs of hold-eligible commands. Returns whether
    /// the event was consumed; otherwise it continues through the normal
    /// routing path.
    private func routeHoldKeyDown(_ event: NSEvent) -> Bool {
        let command = MyTTYKeyBinding(event: event).flatMap { binding in
            MyTTYCommand.allCases.first { bindings[$0] == binding }
        }
        if let command, isAvailable(command), holdEligible(command) {
            heldKeyCode = event.keyCode
            let observe = onKeyPressed
            DispatchQueue.main.async { observe(event) }
            perform(holdRecognizer.keyDown(
                command,
                isRepeat: event.isARepeat
            ))
            return true
        }
        // Any other key settles a pending press as a tap first, so the
        // two actions keep their real order.
        if holdRecognizer.isTracking {
            perform(holdRecognizer.flush())
            if !holdRecognizer.isTracking {
                heldKeyCode = nil
            }
        }
        return false
    }

    private func perform(
        _ actions: [ShortcutHoldRecognizer<MyTTYCommand>.Action]
    ) {
        for action in actions {
            switch action {
            case let .scheduleTimer(generation):
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + holdThreshold
                ) { [weak self] in
                    guard let self else { return }
                    self.perform(
                        self.holdRecognizer.timerFired(
                            generation: generation
                        )
                    )
                }
            case let .performTap(command):
                DispatchQueue.main.async { [weak self] in
                    _ = self?.invoke(command)
                }
            case let .performHold(command):
                let onHold = onHold
                DispatchQueue.main.async {
                    onHold(command)
                }
            }
        }
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
    }

    func update(bindings: [MyTTYCommand: MyTTYKeyBinding]) {
        self.bindings = bindings
    }

    static func route(
        _ event: NSEvent,
        bindings: [MyTTYCommand: MyTTYKeyBinding],
        isAvailable: (MyTTYCommand) -> Bool = { _ in true },
        schedule: (@escaping @MainActor () -> Void) -> Void,
        invoke: @escaping (MyTTYCommand) -> Bool
    ) -> NSEvent? {
        guard event.type == .keyDown,
              let binding = MyTTYKeyBinding(event: event),
              let command = MyTTYCommand.allCases.first(where: {
                  bindings[$0] == binding
              }),
              isAvailable(command)
        else { return event }
        schedule { _ = invoke(command) }
        return nil
    }

    static func routeAndObserve(
        _ event: NSEvent,
        bindings: [MyTTYCommand: MyTTYKeyBinding],
        isAvailable: (MyTTYCommand) -> Bool = { _ in true },
        schedule: (@escaping @MainActor () -> Void) -> Void,
        observe: @escaping (NSEvent) -> Void,
        invoke: @escaping (MyTTYCommand) -> Bool
    ) -> NSEvent? {
        let routed = route(
            event,
            bindings: bindings,
            isAvailable: isAvailable,
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
