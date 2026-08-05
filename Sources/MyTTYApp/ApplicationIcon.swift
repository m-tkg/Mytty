import AppKit
import os

/// Every dialog presentation in this file logs first and never blocks the
/// main actor -- `ControlServer.process` runs `mytty-ctl` requests on the
/// main actor too, so an `NSAlert.runModal()` anywhere blocks every other
/// in-flight control-socket request until a human clicks a button.
let dialogLog = Logger(subsystem: "dev.mytty.dialogs", category: "presentation")

enum ApplicationIcon {
    static let image: NSImage? = {
        guard let url = ApplicationResources.resourceURL(
            named: "AppIcon",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }()
}

@MainActor
enum ApplicationAlert {
    static func make(style: NSAlert.Style = .informational) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.icon = ApplicationIcon.image
        return alert
    }

    /// Awaits the user's answer to `alert`, presented as a sheet on
    /// `window` when one is available or, failing that, as a detached
    /// panel that doesn't activate the app or block anything. Always use
    /// this (or `present(_:on:)`) instead of `NSAlert.runModal()`.
    static func present(
        _ alert: NSAlert,
        on window: NSWindow?
    ) async -> NSApplication.ModalResponse {
        if let window {
            return await presentSheet(alert, on: window)
        }
        return await presentDetached(alert)
    }

    static func presentSheet(
        _ alert: NSAlert,
        on window: NSWindow
    ) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    /// Fallback for when no window exists to host a sheet (every window
    /// closed while a control-socket request still needs a human answer).
    /// `NSAlert` has no non-modal, non-sheet presentation of its own, so
    /// this wires the alert's buttons to a continuation directly instead
    /// of using `runModal()`'s blocking event loop.
    static func presentDetached(
        _ alert: NSAlert
    ) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            let responder = AlertButtonResponder(alert: alert) { response in
                alert.window.orderOut(nil)
                continuation.resume(returning: response)
            }
            responder.retainUntilResponse()
            alert.window.center()
            alert.window.orderFrontRegardless()
        }
    }

    /// Panel counterpart of `present(_:on:)`: `NSSavePanel`/`NSOpenPanel`
    /// already have non-blocking, non-modal presentations built in
    /// (`begin(completionHandler:)`), so no button-wiring trick is needed
    /// for the windowless fallback.
    static func present(
        _ panel: NSSavePanel,
        on window: NSWindow?
    ) async -> NSApplication.ModalResponse {
        if let window {
            return await presentSheet(panel, on: window)
        }
        return await presentDetached(panel)
    }

    static func presentSheet(
        _ panel: NSSavePanel,
        on window: NSWindow
    ) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    static func presentDetached(
        _ panel: NSSavePanel
    ) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}

/// Backs `ApplicationAlert.presentDetached(_:NSAlert)`: retargets each
/// button so a click resolves the continuation instead of the modal
/// session `runModal()` would otherwise pump.
@MainActor
private final class AlertButtonResponder: NSObject {
    private var onResponse: ((NSApplication.ModalResponse) -> Void)?
    private var retained: AlertButtonResponder?

    init(
        alert: NSAlert,
        onResponse: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        self.onResponse = onResponse
        super.init()
        for (index, button) in alert.buttons.enumerated() {
            button.tag = index
            button.target = self
            button.action = #selector(handleButton(_:))
        }
    }

    /// Keeps this responder alive until a button fires -- nothing else
    /// holds a reference to it once `present(_:on:)` returns.
    func retainUntilResponse() {
        retained = self
    }

    @objc private func handleButton(_ sender: NSButton) {
        let response = NSApplication.ModalResponse(
            rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                + sender.tag
        )
        onResponse?(response)
        onResponse = nil
        retained = nil
    }
}
