import Carbon.HIToolbox
import MyTTYCore

/// Wraps Carbon's `RegisterEventHotKey` so the floating terminal panel
/// (issue #103) has a hot key that works system-wide, not only while Mytty
/// is frontmost. `NSEvent.addGlobalMonitorForEvents` was ruled out for this:
/// it needs Accessibility permission and can only observe, never consume,
/// so the combination would still reach whatever app is actually
/// frontmost. Mytty ships unsandboxed (`.entitlements` only exists for the
/// iOS target), so `RegisterEventHotKey` carries none of the App Store
/// sandbox's restrictions here.
@MainActor
final class GlobalHotKeyRegistrar {
    private static let signature: OSType = fourCharCode("mtty")

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private let hotKeyID = EventHotKeyID(signature: signature, id: 1)

    /// Registers `binding` as the system-wide hot key, replacing any
    /// previous registration first. Returns whether registration
    /// succeeded -- it fails when another app already owns the same
    /// combination, which the caller (Settings) surfaces to the user.
    @discardableResult
    func register(
        binding: MyTTYKeyBinding,
        handler: @escaping () -> Void
    ) -> Bool {
        unregister()
        guard let hotKey = CarbonKeyCode.hotKey(for: binding) else {
            return false
        }
        self.handler = handler
        installEventHandlerIfNeeded()

        var registeredRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )
        guard status == noErr, let registeredRef else { return false }
        hotKeyRef = registeredRef
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    isolated deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Installs the process-wide Carbon event handler once; every
    /// registration after the first reuses it; only the hot key
    /// registration itself is replaced by a later `register(binding:handler:)`.
    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard status == noErr else { return status }
                let registrar = Unmanaged<GlobalHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    guard receivedID.id == registrar.hotKeyID.id else {
                        return
                    }
                    registrar.handler?()
                }
                return noErr
            },
            1,
            &spec,
            userData,
            &eventHandlerRef
        )
    }
}

/// Packs a 4-character string into the `OSType` Carbon hot key signatures
/// use. Only needs to be a stable, Mytty-specific value -- it isn't
/// interpreted by the system, just echoed back in the event so a handler
/// installed by another instance can't be mistaken for this one.
private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(OSType(0)) { accumulated, byte in
        (accumulated << 8) | OSType(byte)
    }
}
