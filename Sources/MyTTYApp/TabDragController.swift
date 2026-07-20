import AppKit
import MyTTYCore
import SwiftUI
import UniformTypeIdentifiers

/// Owns the tab-tear-off drag gesture: building the `NSDraggingItem`/
/// preview image, driving the `NSDraggingSession` as its
/// `NSDraggingSource`, and routing a drop back to either an in-window
/// reorder or a cross-window transfer via the shared `TabDragCoordinator`.
/// Extracted from `TerminalWindowController.startTabDragSession` /
/// `handleTabDrop` / `handleTabDragSessionEnded` / `makeTabDragImage` /
/// the `NSDraggingSource` conformance verbatim.
///
/// `TabDragCoordinator` is a single instance shared by every window
/// (`AppDelegate` owns it, since a cross-window drag's payload must be
/// visible to both the source and target window's controller) and is
/// handed in here rather than constructed locally.
///
/// `beginTabTransfer`/`adopt`/`performTabMove` (and its `move`/`reorder`
/// callers) stay on `TerminalWindowController`: none of them touch
/// `tabDragCoordinator`, and moving them would mean threading nearly all
/// of the controller's surface/browser/session plumbing through closures
/// here for no benefit — the same "don't drag orchestration state through
/// a coordinator boundary it doesn't own" call made for `attachSelectedTab`
/// in `PaneLayoutController`. `handleDrop`'s actual reorder instead calls
/// back into the controller via `onMove`.
@MainActor
final class TabDragController: NSObject {
    private let coordinator: TabDragCoordinator

    private let windowID: () -> WindowID
    private let window: () -> NSWindow?
    private let tabExists: (TabID) -> Bool
    private let tabIndex: (TabID) -> Int?
    private let sidebarRow: (TabID) -> TabSidebarRow?
    private let selectedTabID: () -> TabID?
    private let tabPlacement: () -> MyTTYTabPlacement
    private let localizer: () -> MyTTYLocalizer
    private let clearPromotedDragTabID: () -> Void
    private let onTabDropRequested: (Int) -> Void
    private let onMove: (TabID, Int) -> Void
    private let onTabDragSessionEnded: (TabID, NSPoint) -> Void

    init(
        coordinator: TabDragCoordinator,
        windowID: @escaping () -> WindowID,
        window: @escaping () -> NSWindow?,
        tabExists: @escaping (TabID) -> Bool,
        tabIndex: @escaping (TabID) -> Int?,
        sidebarRow: @escaping (TabID) -> TabSidebarRow?,
        selectedTabID: @escaping () -> TabID?,
        tabPlacement: @escaping () -> MyTTYTabPlacement,
        localizer: @escaping () -> MyTTYLocalizer,
        clearPromotedDragTabID: @escaping () -> Void,
        onTabDropRequested: @escaping (Int) -> Void,
        onMove: @escaping (TabID, Int) -> Void,
        onTabDragSessionEnded: @escaping (TabID, NSPoint) -> Void
    ) {
        self.coordinator = coordinator
        self.windowID = windowID
        self.window = window
        self.tabExists = tabExists
        self.tabIndex = tabIndex
        self.sidebarRow = sidebarRow
        self.selectedTabID = selectedTabID
        self.tabPlacement = tabPlacement
        self.localizer = localizer
        self.clearPromotedDragTabID = clearPromotedDragTabID
        self.onTabDropRequested = onTabDropRequested
        self.onMove = onMove
        self.onTabDragSessionEnded = onTabDragSessionEnded
        super.init()
    }

    /// Whether a tab drag started by this window or another is currently
    /// in flight and not yet consumed by a drop.
    var isDragActive: Bool {
        coordinator.payload != nil && !coordinator.isConsumed
    }

    func beginDrag(for tabID: TabID) {
        guard coordinator.payload == nil,
              tabExists(tabID),
              let window = window(),
              let contentView = window.contentView,
              let event = NSApplication.shared.currentEvent,
              event.type == .leftMouseDragged
                  || event.type == .leftMouseDown,
              let row = sidebarRow(tabID)
        else {
            clearPromotedDragTabID()
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            tabID.rawValue.uuidString,
            forType: TabDragPasteboard.pasteboardType
        )
        pasteboardItem.setString(
            tabID.rawValue.uuidString,
            forType: .string
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = Self.makeTabDragImage(
            row: row,
            placement: tabPlacement(),
            selected: selectedTabID() == tabID,
            localizer: localizer(),
            scale: window.backingScaleFactor,
            colorScheme: window.effectiveAppearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua ? .dark : .light
        )
        let location = contentView.convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            NSRect(
                x: location.x - image.size.width / 2,
                y: location.y - image.size.height / 2,
                width: max(image.size.width, 1),
                height: max(image.size.height, 1)
            ),
            contents: image
        )
        coordinator.begin(tabID: tabID, windowID: windowID())
        let draggingSession = contentView.beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        draggingSession.animatesToStartingPositionsOnCancelOrFail = false
    }

    func handleDrop(at insertionIndex: Int) {
        guard let payload = coordinator.payload,
              !coordinator.isConsumed
        else { return }
        guard payload.windowID == windowID() else {
            onTabDropRequested(insertionIndex)
            return
        }
        guard let sourceIndex = tabIndex(payload.tabID) else { return }
        coordinator.consume()
        guard let destination = TabDropInsertionPlan.moveDestination(
            sourceIndex: sourceIndex,
            insertionIndex: insertionIndex
        ) else { return }
        onMove(payload.tabID, destination)
    }

    private func handleDragSessionEnded(at screenPoint: NSPoint) {
        clearPromotedDragTabID()
        guard let payload = coordinator.payload,
              payload.windowID == windowID()
        else { return }
        onTabDragSessionEnded(payload.tabID, screenPoint)
    }

    private static func makeTabDragImage(
        row: TabSidebarRow,
        placement: MyTTYTabPlacement,
        selected: Bool,
        localizer: MyTTYLocalizer,
        scale: CGFloat,
        colorScheme: ColorScheme
    ) -> NSImage {
        let preview = TabDragPreview(
            row: row,
            placement: placement,
            selected: selected,
            localizer: localizer
        )
        .frame(width: placement.isVertical ? 220 : nil)
        .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = max(scale, 1)
        return renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
    }
}

extension TabDragController: NSDraggingSource {
    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        MainActor.assumeIsolated {
            handleDragSessionEnded(at: screenPoint)
        }
    }
}
