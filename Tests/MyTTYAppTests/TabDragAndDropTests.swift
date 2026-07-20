import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Tab drag and drop")
struct TabDragAndDropTests {
    @Test("promotes a drag to a cross-window session outside the tab area")
    func dragPromotion() {
        let tabArea = CGSize(width: 220, height: 500)

        #expect(!TabDragPromotionPlan.shouldPromote(
            location: CGPoint(x: 110, y: 250),
            tabAreaSize: tabArea
        ))
        #expect(!TabDragPromotionPlan.shouldPromote(
            location: CGPoint(x: 0, y: 0),
            tabAreaSize: tabArea
        ))
        #expect(TabDragPromotionPlan.shouldPromote(
            location: CGPoint(x: 260, y: 250),
            tabAreaSize: tabArea
        ))
        #expect(TabDragPromotionPlan.shouldPromote(
            location: CGPoint(x: 110, y: 520),
            tabAreaSize: tabArea
        ))
        #expect(TabDragPromotionPlan.shouldPromote(
            location: CGPoint(x: -20, y: 250),
            tabAreaSize: tabArea
        ))
    }

    @Test("maps a drop on a row to an insertion index by row half")
    func dropInsertionIndex() {
        let verticalRow = CGSize(width: 208, height: 50)
        let horizontalRow = CGSize(width: 190, height: 40)

        #expect(TabDropInsertionPlan.insertionIndex(
            rowIndex: 2,
            location: CGPoint(x: 100, y: 10),
            rowSize: verticalRow,
            placement: .left
        ) == 2)
        #expect(TabDropInsertionPlan.insertionIndex(
            rowIndex: 2,
            location: CGPoint(x: 100, y: 40),
            rowSize: verticalRow,
            placement: .right
        ) == 3)
        #expect(TabDropInsertionPlan.insertionIndex(
            rowIndex: 1,
            location: CGPoint(x: 40, y: 20),
            rowSize: horizontalRow,
            placement: .top
        ) == 1)
        #expect(TabDropInsertionPlan.insertionIndex(
            rowIndex: 1,
            location: CGPoint(x: 150, y: 20),
            rowSize: horizontalRow,
            placement: .bottom
        ) == 2)
    }

    @Test("converts an insertion index to a reorder destination")
    func reorderDestination() {
        #expect(TabDropInsertionPlan.moveDestination(
            sourceIndex: 0,
            insertionIndex: 3
        ) == 2)
        #expect(TabDropInsertionPlan.moveDestination(
            sourceIndex: 2,
            insertionIndex: 0
        ) == 0)
        #expect(TabDropInsertionPlan.moveDestination(
            sourceIndex: 1,
            insertionIndex: 1
        ) == nil)
        #expect(TabDropInsertionPlan.moveDestination(
            sourceIndex: 1,
            insertionIndex: 2
        ) == nil)
    }

    @Test("tears off into a new window only for unconsumed multi-tab drags")
    func tearOffDecision() {
        #expect(TabTearOffPlan.shouldTearOff(
            isConsumed: false,
            sourceTabCount: 2
        ))
        #expect(!TabTearOffPlan.shouldTearOff(
            isConsumed: true,
            sourceTabCount: 2
        ))
        #expect(!TabTearOffPlan.shouldTearOff(
            isConsumed: false,
            sourceTabCount: 1
        ))
    }

    @Test("places a torn-off window with its top edge at the drop point")
    func tearOffWindowFrame() {
        let frame = TabTearOffPlan.windowFrame(
            endedAt: CGPoint(x: 700, y: 600),
            size: CGSize(width: 1100, height: 720)
        )

        #expect(frame == CGRect(x: 150, y: -120, width: 1100, height: 720))
    }

    @Test("tracks one active drag payload until the session ends")
    @MainActor
    func dragCoordinatorLifecycle() {
        let coordinator = TabDragCoordinator()
        let tabID = TabID()
        let windowID = WindowID()

        #expect(coordinator.payload == nil)
        #expect(!coordinator.isConsumed)

        coordinator.begin(tabID: tabID, windowID: windowID)
        #expect(coordinator.payload?.tabID == tabID)
        #expect(coordinator.payload?.windowID == windowID)
        #expect(!coordinator.isConsumed)

        coordinator.consume()
        #expect(coordinator.isConsumed)
        #expect(coordinator.payload != nil)

        coordinator.end()
        #expect(coordinator.payload == nil)
        #expect(!coordinator.isConsumed)
    }

    @Test("ignores a consume without an active drag")
    @MainActor
    func consumeWithoutActiveDrag() {
        let coordinator = TabDragCoordinator()

        coordinator.consume()

        #expect(!coordinator.isConsumed)
    }
}
