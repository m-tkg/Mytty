import AppKit
import Foundation
import MyTTYCore
import UniformTypeIdentifiers

enum TabDragPasteboard {
    static let identifier = "com.m-tkg.mytty.tab-drag"
    static let pasteboardType = NSPasteboard.PasteboardType(identifier)
    /// Drop targets match on plain text because the custom identifier
    /// is not a declared UTI and would not survive the NSItemProvider
    /// bridge. Foreign text drags are rejected via `validateDrop`,
    /// which requires an in-process drag tracked by TabDragCoordinator.
    static let acceptedTypes: [UTType] = [.plainText]
}

enum TabDragPromotionPlan {
    static func shouldPromote(
        location: CGPoint,
        tabAreaSize: CGSize
    ) -> Bool {
        !CGRect(origin: .zero, size: tabAreaSize).contains(location)
    }
}

enum TabDropInsertionPlan {
    static func insertionIndex(
        rowIndex: Int,
        location: CGPoint,
        rowSize: CGSize,
        placement: MyTTYTabPlacement
    ) -> Int {
        let inLeadingHalf: Bool
        switch placement {
        case .left, .right:
            inLeadingHalf = location.y < rowSize.height / 2
        case .top, .bottom:
            inLeadingHalf = location.x < rowSize.width / 2
        }
        return inLeadingHalf ? rowIndex : rowIndex + 1
    }

    static func moveDestination(
        sourceIndex: Int,
        insertionIndex: Int
    ) -> Int? {
        let destination = insertionIndex > sourceIndex
            ? insertionIndex - 1
            : insertionIndex
        return destination == sourceIndex ? nil : destination
    }
}

enum TabTearOffPlan {
    static func shouldTearOff(
        isConsumed: Bool,
        sourceTabCount: Int
    ) -> Bool {
        !isConsumed && sourceTabCount > 1
    }

    static func windowFrame(
        endedAt point: CGPoint,
        size: CGSize
    ) -> CGRect {
        CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
final class TabDragCoordinator {
    struct Payload: Equatable {
        let tabID: TabID
        let windowID: WindowID
    }

    private(set) var payload: Payload?
    private(set) var isConsumed = false

    func begin(tabID: TabID, windowID: WindowID) {
        payload = Payload(tabID: tabID, windowID: windowID)
        isConsumed = false
    }

    func consume() {
        guard payload != nil else { return }
        isConsumed = true
    }

    func end() {
        payload = nil
        isConsumed = false
    }
}
