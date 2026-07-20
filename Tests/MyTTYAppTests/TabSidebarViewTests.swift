import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Tab sidebar view")
struct TabSidebarViewTests {
    @Test("enables tab movement only when a neighbor exists")
    @MainActor
    func tabMovementAvailability() {
        let ids = [TabID(), TabID(), TabID()]
        let model = TabSidebarModel()
        model.rows = ids.map {
            TabSidebarRow(
                id: $0,
                title: "Tab",
                paneCount: 1,
                attentionCount: 0,
                hasRunningAgent: false
            )
        }

        #expect(!model.canMoveUp(ids[0]))
        #expect(model.canMoveDown(ids[0]))
        #expect(model.canMoveUp(ids[1]))
        #expect(model.canMoveDown(ids[1]))
        #expect(model.canMoveUp(ids[2]))
        #expect(!model.canMoveDown(ids[2]))
    }

    @Test("shows pane counts for every tab")
    func paneCountVisibility() {
        let singlePane = TabSidebarRow(
            id: TabID(),
            title: "Single",
            paneCount: 1,
            attentionCount: 0,
            hasRunningAgent: false
        )
        let multiplePanes = TabSidebarRow(
            id: TabID(),
            title: "Multiple",
            paneCount: 3,
            attentionCount: 0,
            hasRunningAgent: true
        )

        #expect(singlePane.visiblePaneCount == 1)
        #expect(multiplePanes.visiblePaneCount == 3)
        #expect(singlePane.hasStatusIndicators)
        #expect(multiplePanes.hasStatusIndicators)
        #expect(!singlePane.canEqualizePanes)
        #expect(multiplePanes.canEqualizePanes)
    }

    @Test("marks a tab while its other panes are collapsed")
    func paneZoomIndicator() {
        let row = TabSidebarRow(
            id: TabID(),
            title: "Zoomed",
            paneCount: 3,
            attentionCount: 0,
            hasRunningAgent: false,
            hasCollapsedPanes: true
        )

        #expect(row.hasCollapsedPanes)
        #expect(row.hasStatusIndicators)
    }

    @Test("marks the tab that is being recorded")
    func recordingIndicator() {
        let row = TabSidebarRow(
            id: TabID(),
            title: "Recorded",
            paneCount: 1,
            attentionCount: 0,
            hasRunningAgent: false,
            isRecording: true
        )

        #expect(row.isRecording)
        #expect(row.hasStatusIndicators)
    }

    @Test("starts reordering from the entire tab after the drag threshold")
    func tabDragActivation() {
        let policy = TabDragInteractionPolicy.reorder

        #expect(policy.activationArea == .entireTab)
        // High enough that slightly-sloppy clicks stay clicks: once the
        // drag preview starts it cancels the row's buttons.
        #expect(policy.minimumDistance == 8)
    }

    @Test("maps vertical and horizontal tab drags to destinations")
    func tabDragDestinations() {
        let ids = [TabID(), TabID(), TabID()]

        #expect(
            TabReorderPlan.targetID(
                for: ids[2],
                translation: CGSize(width: 0, height: -106),
                placement: .left,
                orderedIDs: ids
            ) == ids[0]
        )
        #expect(
            TabReorderPlan.targetID(
                for: ids[2],
                translation: CGSize(width: 0, height: -106),
                placement: .right,
                orderedIDs: ids
            ) == ids[0]
        )
        #expect(
            TabReorderPlan.targetID(
                for: ids[0],
                translation: CGSize(width: 386, height: 0),
                placement: .top,
                orderedIDs: ids
            ) == ids[2]
        )
        #expect(
            TabReorderPlan.targetID(
                for: ids[0],
                translation: CGSize(width: 386, height: 0),
                placement: .bottom,
                orderedIDs: ids
            ) == ids[2]
        )
        #expect(
            TabReorderPlan.targetID(
                for: ids[1],
                translation: CGSize(width: 0, height: 10),
                placement: .left,
                orderedIDs: ids
            ) == nil
        )
    }

    @Test("presents the dragged tab as a moving translucent copy")
    func tabDragPresentation() {
        let draggedID = TabID()
        let otherID = TabID()
        let translation = CGSize(width: 24, height: 61)
        let presentation = TabDragPresentation(
            tabID: draggedID,
            translation: translation
        )

        #expect(presentation.sourceOpacity(for: draggedID) == 0.35)
        #expect(presentation.sourceOpacity(for: otherID) == 1)
        #expect(presentation.previewOpacity == 0.72)
        #expect(presentation.translation == translation)
    }
}
