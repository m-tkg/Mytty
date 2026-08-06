import Foundation
import Testing

@testable import MyTTYCore

@Suite("Tab session")
struct TabSessionTests {
    @Test("mixes browser and terminal panes while tracking them separately")
    func browserPane() throws {
        let terminal = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(1)),
            workingDirectory: URL(fileURLWithPath: "/repo", isDirectory: true)
        )
        let browser = BrowserPaneState(
            id: TerminalSurfaceID(rawValue: makeUUID(2)),
            url: URL(string: "https://example.com/index.html")!
        )
        var tab = TabSession(initialSurface: terminal)

        try tab.split(browser: browser, direction: .right)

        #expect(tab.paneIDs == [terminal.id, browser.id])
        #expect(tab.surfaceIDs == [terminal.id])
        #expect(tab.focusedSurfaceID == browser.id)
        #expect(tab.root.browserState(with: browser.id) == browser)

        let local = URL(fileURLWithPath: "/tmp/report.html")
        try tab.updateBrowserURL(local, for: browser.id)
        #expect(tab.root.browserState(with: browser.id)?.url == local)

        try tab.close(pane: browser.id)
        #expect(tab.root == .surface(terminal))
        #expect(tab.paneIDs == [terminal.id])
        #expect(tab.focusedSurfaceID == terminal.id)
    }

    @Test("creates a browser-only tab")
    func browserTab() {
        let browser = BrowserPaneState(
            url: URL(fileURLWithPath: "/tmp/index.html")
        )
        let tab = TabSession(initialBrowser: browser)

        #expect(tab.root == .browser(browser))
        #expect(tab.paneIDs == [browser.id])
        #expect(tab.surfaceIDs.isEmpty)
        #expect(tab.focusedSurfaceID == browser.id)
    }

    @Test("starts with one focused terminal surface")
    func initialSurface() {
        let surface = makeSurface(id: 1, path: "/repo")

        let tab = TabSession(id: makeTabID(1), initialSurface: surface)

        #expect(tab.root == .surface(surface))
        #expect(tab.focusedSurfaceID == surface.id)
        #expect(tab.surfaceIDs == [surface.id])
    }

    @Test("does not pin a title just because focus moves to another pane")
    func stableInitialTitle() throws {
        let initial = makeSurface(id: 1, path: "/repo")
        let secondary = makeSurface(id: 2, path: "/other")
        var tab = TabSession(id: makeTabID(1), initialSurface: initial)

        try tab.split(
            surface: initial.id,
            adding: secondary,
            direction: .right
        )

        #expect(tab.focusedSurfaceID == secondary.id)
        #expect(tab.pinnedTitle == nil)
    }

    @Test("splits right and focuses the new surface")
    func splitRight() throws {
        let first = makeSurface(id: 1, path: "/repo")
        let second = makeSurface(id: 2, path: "/repo")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)

        try tab.split(
            surface: first.id,
            adding: second,
            direction: .right
        )

        #expect(
            tab.root == .split(
                orientation: .horizontal,
                ratio: 0.5,
                first: .surface(first),
                second: .surface(second)
            )
        )
        #expect(tab.focusedSurfaceID == second.id)
    }

    @Test("splits without moving focus when focus is false")
    func splitWithoutFocus() throws {
        let first = makeSurface(id: 1, path: "/repo")
        let second = makeSurface(id: 2, path: "/repo")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)

        try tab.split(
            surface: first.id,
            adding: second,
            direction: .right,
            focus: false
        )

        #expect(
            tab.root == .split(
                orientation: .horizontal,
                ratio: 0.5,
                first: .surface(first),
                second: .surface(second)
            )
        )
        #expect(tab.focusedSurfaceID == first.id)
    }

    @Test("places left and upper splits before their target")
    func splitBeforeTarget() throws {
        let original = makeSurface(id: 1, path: "/repo")
        let left = makeSurface(id: 2, path: "/left")
        let upper = makeSurface(id: 3, path: "/upper")
        var tab = TabSession(id: makeTabID(1), initialSurface: original)

        try tab.split(surface: original.id, adding: left, direction: .left)
        try tab.split(surface: original.id, adding: upper, direction: .up)

        #expect(
            tab.root == .split(
                orientation: .horizontal,
                ratio: 0.5,
                first: .surface(left),
                second: .split(
                    orientation: .vertical,
                    ratio: 0.5,
                    first: .surface(upper),
                    second: .surface(original)
                )
            )
        )
        #expect(tab.focusedSurfaceID == upper.id)
    }

    @Test("collapses a split and moves focus to its neighbor")
    func closeFocusedSurface() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)

        try tab.close(surface: second.id)

        #expect(tab.root == .surface(first))
        #expect(tab.focusedSurfaceID == first.id)
    }

    @Test("rejects invalid mutations without changing the tab")
    func invalidMutations() throws {
        let surface = makeSurface(id: 1, path: "/repo")
        let unknown = makeSurface(id: 9, path: "/unknown")
        var tab = TabSession(id: makeTabID(1), initialSurface: surface)
        let original = tab

        #expect(throws: TabSessionError.surfaceNotFound(unknown.id)) {
            try tab.focus(surface: unknown.id)
        }
        #expect(throws: TabSessionError.surfaceNotFound(unknown.id)) {
            try tab.split(
                surface: unknown.id,
                adding: makeSurface(id: 2, path: "/new"),
                direction: .down
            )
        }
        #expect(throws: TabSessionError.cannotCloseLastSurface) {
            try tab.close(surface: surface.id)
        }
        #expect(tab == original)
    }

    @Test("swaps two panes while preserving split ratios and structure")
    func swapPanes() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        let third = makeSurface(id: 3, path: "/third")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        try tab.split(surface: first.id, adding: third, direction: .down)
        try tab.updateSplitRatio(0.3, at: [.first])

        try tab.swapPanes(first.id, second.id)

        #expect(
            tab.root == .split(
                orientation: .horizontal,
                ratio: 0.5,
                first: .split(
                    orientation: .vertical,
                    ratio: 0.3,
                    first: .surface(second),
                    second: .surface(third)
                ),
                second: .surface(first)
            )
        )
        #expect(Set(tab.paneIDs) == Set([first.id, second.id, third.id]))
    }

    @Test("swapping a pane with itself is a no-op")
    func swapPanesNoOp() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        let original = tab

        try tab.swapPanes(first.id, first.id)

        #expect(tab == original)
    }

    @Test("rejects swapping an unknown pane")
    func swapPanesRejectsUnknownID() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        let unknown = makeSurface(id: 9, path: "/unknown")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        let original = tab

        #expect(throws: TabSessionError.surfaceNotFound(unknown.id)) {
            try tab.swapPanes(first.id, unknown.id)
        }
        #expect(tab == original)
    }

    @Test("rejects duplicate surface identifiers")
    func duplicateSurface() throws {
        let surface = makeSurface(id: 1, path: "/repo")
        var tab = TabSession(id: makeTabID(1), initialSurface: surface)

        #expect(throws: TabSessionError.duplicateSurface(surface.id)) {
            try tab.split(
                surface: surface.id,
                adding: surface,
                direction: .down
            )
        }
    }

    @Test("moves focus to the nearest pane in a requested direction")
    func directionalFocus() throws {
        let left = makeSurface(id: 1, path: "/left")
        let upperRight = makeSurface(id: 2, path: "/upper-right")
        let lowerRight = makeSurface(id: 3, path: "/lower-right")
        var tab = TabSession(id: makeTabID(1), initialSurface: left)
        try tab.split(
            surface: left.id,
            adding: upperRight,
            direction: .right
        )
        try tab.split(
            surface: upperRight.id,
            adding: lowerRight,
            direction: .down
        )
        try tab.focus(surface: left.id)

        let movedRight = tab.focus(in: .right)
        #expect(movedRight)
        #expect(tab.focusedSurfaceID == upperRight.id)
        let movedDown = tab.focus(in: .down)
        #expect(movedDown)
        #expect(tab.focusedSurfaceID == lowerRight.id)
        let movedLeft = tab.focus(in: .left)
        #expect(movedLeft)
        #expect(tab.focusedSurfaceID == left.id)
        let movedPastEdge = tab.focus(in: .left)
        #expect(!movedPastEdge)
        #expect(tab.focusedSurfaceID == left.id)
    }

    @Test("updates a nested divider ratio by split path")
    func dividerRatio() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        let third = makeSurface(id: 3, path: "/third")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        try tab.split(surface: second.id, adding: third, direction: .down)

        try tab.updateSplitRatio(0.7, at: [.second])

        guard case let .split(_, outerRatio, _, right) = tab.root,
              case let .split(_, nestedRatio, _, _) = right
        else {
            Issue.record("Expected nested split tree")
            return
        }
        #expect(outerRatio == 0.5)
        #expect(nestedRatio == 0.7)
        #expect(throws: TabSessionError.splitNotFound) {
            try tab.updateSplitRatio(0.4, at: [.first])
        }
    }

    @Test("equalizes consecutive splits by pane count")
    func equalizeConsecutiveSplits() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        let third = makeSurface(id: 3, path: "/third")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        try tab.split(surface: second.id, adding: third, direction: .right)
        try tab.updateSplitRatio(0.8, at: [])
        try tab.updateSplitRatio(0.7, at: [.second])

        tab.equalizePanes()

        guard case let .split(_, outerRatio, _, trailing) = tab.root,
              case let .split(_, nestedRatio, _, _) = trailing
        else {
            Issue.record("Expected consecutive horizontal splits")
            return
        }
        #expect(abs(outerRatio - 1.0 / 3.0) < 0.0001)
        #expect(abs(nestedRatio - 0.5) < 0.0001)
    }

    @Test("equalizes perpendicular splits as independent regions")
    func equalizePerpendicularSplits() throws {
        let left = makeSurface(id: 1, path: "/left")
        let upperRight = makeSurface(id: 2, path: "/upper-right")
        let lowerRight = makeSurface(id: 3, path: "/lower-right")
        var tab = TabSession(id: makeTabID(1), initialSurface: left)
        try tab.split(
            surface: left.id,
            adding: upperRight,
            direction: .right
        )
        try tab.split(
            surface: upperRight.id,
            adding: lowerRight,
            direction: .down
        )
        try tab.updateSplitRatio(0.8, at: [])
        try tab.updateSplitRatio(0.7, at: [.second])

        tab.equalizePanes()

        guard case let .split(_, outerRatio, _, right) = tab.root,
              case let .split(_, nestedRatio, _, _) = right
        else {
            Issue.record("Expected perpendicular split tree")
            return
        }
        #expect(abs(outerRatio - 0.5) < 0.0001)
        #expect(abs(nestedRatio - 0.5) < 0.0001)
    }

    @Test("decodes isOrchestrated as false when the key is absent")
    func decodesMissingIsOrchestratedAsFalse() throws {
        let json = """
        {
            "id": { "rawValue": "\(makeUUID(1).uuidString)" },
            "workingDirectory": "file:///repo/"
        }
        """
        let state = try JSONDecoder().decode(
            TerminalSurfaceState.self,
            from: Data(json.utf8)
        )
        #expect(state.isOrchestrated == false)
    }

    @Test("round-trips isOrchestrated through encode/decode")
    func roundTripsIsOrchestrated() throws {
        let surface = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(1)),
            workingDirectory: URL(fileURLWithPath: "/repo", isDirectory: true),
            isOrchestrated: true
        )

        let encoded = try JSONEncoder().encode(surface)
        let decoded = try JSONDecoder().decode(
            TerminalSurfaceState.self,
            from: encoded
        )

        #expect(decoded.isOrchestrated == true)
        #expect(decoded == surface)
    }

    @Test("round-trips createdAt through encode/decode")
    func roundTripsCreatedAt() throws {
        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let tab = TabSession(
            id: makeTabID(1),
            initialSurface: makeSurface(id: 2, path: "/repo"),
            createdAt: createdAt
        )

        let encoded = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(
            TabSession.self,
            from: encoded
        )

        #expect(decoded.createdAt == createdAt)
        #expect(decoded == tab)
    }

    @Test("decodes createdAt as now when the key is absent")
    func decodesMissingCreatedAtAsNow() throws {
        let json = """
        {
            "id": { "rawValue": "\(makeUUID(1).uuidString)" },
            "root": {
                "surface": {
                    "_0": {
                        "id": { "rawValue": "\(makeUUID(2).uuidString)" },
                        "workingDirectory": "file:///repo/",
                        "isOrchestrated": false
                    }
                }
            },
            "focusedSurfaceID": { "rawValue": "\(makeUUID(2).uuidString)" }
        }
        """
        let before = Date()
        let tab = try JSONDecoder().decode(
            TabSession.self,
            from: Data(json.utf8)
        )
        let after = Date()

        #expect(tab.createdAt >= before)
        #expect(tab.createdAt <= after)
    }

    @Test("outer split wraps the whole tab layout, not the focused pane")
    func splitOuterWrapsRoot() throws {
        let top = makeSurface(id: 1, path: "/top")
        let bottom = makeSurface(id: 2, path: "/bottom")
        var tab = TabSession(id: makeTabID(1), initialSurface: top)
        try tab.split(surface: top.id, adding: bottom, direction: .down)
        try tab.focus(surface: top.id)

        let outer = makeSurface(id: 3, path: "/outer")
        try tab.splitOuter(adding: outer, direction: .right)

        #expect(
            tab.root == .split(
                orientation: .horizontal,
                ratio: 0.5,
                first: .split(
                    orientation: .vertical,
                    ratio: 0.5,
                    first: .surface(top),
                    second: .surface(bottom)
                ),
                second: .surface(outer)
            )
        )
        #expect(tab.focusedSurfaceID == outer.id)
    }

    @Test("outer split places left and upper panes before the layout")
    func splitOuterBeforeRoot() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)

        let upper = makeSurface(id: 3, path: "/upper")
        try tab.splitOuter(adding: upper, direction: .up)

        #expect(
            tab.root == .split(
                orientation: .vertical,
                ratio: 0.5,
                first: .surface(upper),
                second: .split(
                    orientation: .horizontal,
                    ratio: 0.5,
                    first: .surface(first),
                    second: .surface(second)
                )
            )
        )
        #expect(tab.focusedSurfaceID == upper.id)
    }

    @Test("outer split rejects duplicate surface identifiers")
    func splitOuterRejectsDuplicates() throws {
        let surface = makeSurface(id: 1, path: "/repo")
        var tab = TabSession(id: makeTabID(1), initialSurface: surface)
        let before = tab

        #expect(throws: TabSessionError.duplicateSurface(surface.id)) {
            try tab.splitOuter(adding: surface, direction: .right)
        }
        #expect(tab == before)
    }

    @Test("detaches a pane and returns its leaf, refocusing a survivor")
    func detachPane() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        #expect(tab.focusedSurfaceID == second.id)

        let leaf = try tab.detach(pane: second.id)

        #expect(leaf == .surface(second))
        #expect(tab.root == .surface(first))
        #expect(tab.paneIDs == [first.id])
        #expect(tab.focusedSurfaceID == first.id)
    }

    @Test("detach rejects the last remaining pane and unknown identifiers")
    func detachRejectsInvalidTargets() throws {
        let surface = makeSurface(id: 1, path: "/repo")
        let unknown = makeSurface(id: 9, path: "/unknown")
        var tab = TabSession(id: makeTabID(1), initialSurface: surface)
        let original = tab

        #expect(throws: TabSessionError.cannotCloseLastSurface) {
            _ = try tab.detach(pane: surface.id)
        }
        #expect(throws: TabSessionError.surfaceNotFound(unknown.id)) {
            _ = try tab.detach(pane: unknown.id)
        }
        #expect(tab == original)
    }

    @Test("balanced insertion fills horizontally before stacking, for a wide container")
    func balancedInsertionSequence() throws {
        // Six sequential insertions at a wide (1.6) aspect ratio: each
        // assertion captures `target` *before* performing that split, so
        // this documents the exact greedy sequence
        // `BalancedPaneInsertion` produces -- largest pane (ties broken
        // by simulated row balance, then top-left position), longer
        // side -- rather than asserting a full final snapshot. See
        // `BalancedPaneInsertion.target`'s doc comment for why this
        // converges on a near-square, horizontally-first grid: 2
        // side-by-side, then 2x2-ish at 3-4, top-3/bottom-2 at 5, and a
        // proper 3-column x 2-row grid at 6 -- never a 1x6 strip, and
        // never the 4-top/2-bottom shape a plain top-left tie-break
        // would settle for at 6.
        let pane0 = makeSurface(id: 1, path: "/p0")
        var tab = TabSession(id: makeTabID(1), initialSurface: pane0)
        let pane1 = makeSurface(id: 2, path: "/p1")
        let pane2 = makeSurface(id: 3, path: "/p2")
        let pane3 = makeSurface(id: 4, path: "/p3")
        let pane4 = makeSurface(id: 5, path: "/p4")
        let pane5 = makeSurface(id: 6, path: "/p5")

        // 1 -> 2: the lone pane is wider than tall, so it splits right.
        var target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )
        #expect(target?.paneID == pane0.id)
        #expect(target?.direction == .right)
        try tab.split(surface: pane0.id, adding: pane1, direction: .right)

        // 2 -> 3: both halves are now taller than wide (0.8 x 1); tied
        // on area and on the row-balance score (splitting either one
        // merges into a single row of 3 either way), so pane0 wins the
        // top-left tie-break.
        target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )
        #expect(target?.paneID == pane0.id)
        #expect(target?.direction == .down)
        try tab.split(surface: pane0.id, adding: pane2, direction: .down)

        // 3 -> 4: pane1's whole right half (0.8 x 1, area 0.8) is now
        // the unique largest remaining pane -- no tie to break.
        target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )
        #expect(target?.paneID == pane1.id)
        #expect(target?.direction == .down)
        try tab.split(surface: pane1.id, adding: pane3, direction: .down)

        // 4 -> 5: a 2x2 grid, all four panes tied at 0.8 x 0.5 (area
        // 0.4) and tied on row-balance score too (every candidate splits
        // into a 3/1 row split); pane0 (top-left) wins the position
        // tie-break.
        target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )
        #expect(target?.paneID == pane0.id)
        #expect(target?.direction == .right)
        try tab.split(surface: pane0.id, adding: pane4, direction: .right)

        // 5 -> 6: pane1 (top-right), pane2 (bottom-left), and pane3
        // (bottom-right) all tie on area (0.8 x 0.5). Splitting pane1
        // would leave a 4-top/2-bottom layout (row-balance score 2);
        // splitting pane2 or pane3 instead produces two even rows of 3
        // (score 0) -- this is the tie-break that keeps 6 panes a
        // proper grid instead of a lopsided strip. pane2 and pane3 tie
        // on that score, so pane2 (top-left of the two) wins.
        target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )
        #expect(target?.paneID == pane2.id)
        #expect(target?.direction == .right)
        try tab.split(surface: pane2.id, adding: pane5, direction: .right)

        #expect(tab.paneIDs.count == 6)
        // Horizontal-first, near-square growth: a top row of pane0,
        // pane4, pane1 and a bottom row of pane2, pane5, pane3 -- three
        // columns, two rows -- never a 1x6 strip and never a lopsided
        // 4-top/2-bottom split.
        #expect(tab.root.neighbor(of: pane0.id, in: .right) == pane4.id)
        #expect(tab.root.neighbor(of: pane4.id, in: .right) == pane1.id)
        #expect(tab.root.neighbor(of: pane2.id, in: .right) == pane5.id)
        #expect(tab.root.neighbor(of: pane5.id, in: .right) == pane3.id)
        #expect(tab.root.neighbor(of: pane0.id, in: .down) == pane2.id)
        #expect(tab.root.neighbor(of: pane1.id, in: .down) == pane3.id)

        // Assert the 3-column x 2-row shape directly via row clustering
        // of the final frames, not just the direction sequence that
        // produced it.
        let rows = BalancedPaneInsertion.rowGroups(
            in: tab.root,
            containerAspectRatio: 1.6
        )
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.count == 3 })
        let rowSets = Set(rows.map(Set.init))
        #expect(rowSets.contains(Set([pane0.id, pane4.id, pane1.id])))
        #expect(rowSets.contains(Set([pane2.id, pane5.id, pane3.id])))
    }

    @Test("balanced insertion stays deterministic beyond six panes")
    func balancedInsertionDeterministicBeyondSixPanes() throws {
        // 7+ panes are only required to stay near-square and
        // deterministic, not to match a specific hand-derived shape --
        // repeatedly inserting at the balanced target from the same
        // root must always choose the same (pane, direction), and the
        // resulting layout must actually contain the new pane.
        var tab = TabSession(
            id: makeTabID(1),
            initialSurface: makeSurface(id: 1, path: "/p0")
        )
        for step in 2...8 {
            let first = BalancedPaneInsertion.target(
                in: tab.root,
                containerAspectRatio: 1.6
            )
            let second = BalancedPaneInsertion.target(
                in: tab.root,
                containerAspectRatio: 1.6
            )
            #expect(first?.paneID == second?.paneID)
            #expect(first?.direction == second?.direction)
            guard let target = first else {
                Issue.record("expected a target at \(tab.paneIDs.count) panes")
                return
            }
            let added = makeSurface(id: UInt8(step), path: "/p\(step)")
            try tab.split(
                surface: target.paneID,
                adding: added,
                direction: target.direction
            )
            #expect(tab.paneIDs.contains(added.id))
        }
        #expect(tab.paneIDs.count == 8)
    }

    @Test("prefers a terminal-surface leaf over an equal-size browser pane")
    func balancedInsertionPrefersTerminalLeaves() throws {
        let terminal = makeSurface(id: 1, path: "/repo")
        let browser = BrowserPaneState(
            id: TerminalSurfaceID(rawValue: makeUUID(2)),
            url: URL(string: "https://example.com")!
        )
        var tab = TabSession(id: makeTabID(1), initialSurface: terminal)
        // Equal-size leaves so a pure largest-area rule would be free to
        // pick either -- a tab with at least one terminal leaf must
        // still prefer it over the browser pane.
        try tab.split(browser: browser, direction: .right)

        let target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )
        #expect(target?.paneID == terminal.id)
    }

    @Test("falls back to any leaf when a tab has no terminal panes")
    func balancedInsertionFallsBackWithoutTerminalLeaves() throws {
        let browser = BrowserPaneState(
            id: TerminalSurfaceID(rawValue: makeUUID(1)),
            url: URL(string: "https://example.com")!
        )
        let tab = TabSession(id: makeTabID(1), initialBrowser: browser)

        let target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )

        #expect(target?.paneID == browser.id)
    }

    @Test("tie-breaks equal-area panes by top-left position")
    func balancedInsertionTieBreaksTopLeft() throws {
        // Four equal-area panes arranged as a 2x2 grid: the algorithm
        // must deterministically pick the top-left one, not whichever
        // happens to sort first structurally.
        let topLeft = makeSurface(id: 1, path: "/tl")
        let topRight = makeSurface(id: 2, path: "/tr")
        let bottomLeft = makeSurface(id: 3, path: "/bl")
        let bottomRight = makeSurface(id: 4, path: "/br")
        var tab = TabSession(id: makeTabID(1), initialSurface: topLeft)
        try tab.split(surface: topLeft.id, adding: topRight, direction: .right)
        try tab.split(
            surface: topLeft.id,
            adding: bottomLeft,
            direction: .down
        )
        try tab.split(
            surface: topRight.id,
            adding: bottomRight,
            direction: .down
        )

        let target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: 1.6
        )

        #expect(target?.paneID == topLeft.id)
    }

    @Test("attaches a pane node at the outer right edge and focuses it")
    func attachPane() throws {
        let first = makeSurface(id: 1, path: "/first")
        let attached = makeSurface(id: 2, path: "/attached")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)

        try tab.attach(pane: .surface(attached))

        #expect(
            tab.root == .split(
                orientation: .horizontal,
                ratio: 0.5,
                first: .surface(first),
                second: .surface(attached)
            )
        )
        #expect(tab.focusedSurfaceID == attached.id)
    }

    @Test("detaches and reattaches a browser pane")
    func detachAndAttachBrowserPane() throws {
        let terminal = makeSurface(id: 1, path: "/repo")
        let browser = BrowserPaneState(
            id: TerminalSurfaceID(rawValue: makeUUID(2)),
            url: URL(string: "https://example.com")!
        )
        var source = TabSession(id: makeTabID(1), initialSurface: terminal)
        try source.split(browser: browser, direction: .right)
        var destination = TabSession(
            id: makeTabID(2),
            initialSurface: makeSurface(id: 3, path: "/destination")
        )

        let leaf = try source.detach(pane: browser.id)
        try destination.attach(pane: leaf)

        #expect(leaf == .browser(browser))
        #expect(source.paneIDs == [terminal.id])
        #expect(destination.paneIDs.contains(browser.id))
        #expect(destination.focusedSurfaceID == browser.id)
        #expect(destination.root.browserState(with: browser.id) == browser)
    }

    @Test("attach rejects a node whose pane ID already exists in the tab")
    func attachRejectsDuplicates() throws {
        let surface = makeSurface(id: 1, path: "/repo")
        var tab = TabSession(id: makeTabID(1), initialSurface: surface)
        let before = tab

        #expect(throws: TabSessionError.duplicateSurface(surface.id)) {
            try tab.attach(pane: .surface(surface))
        }
        #expect(tab == before)
    }

    @Test("attachBalanced places a node at the balanced target, not the outer edge")
    func attachBalancedPlacesAtBalancedTarget() throws {
        let pane0 = makeSurface(id: 1, path: "/p0")
        var tab = TabSession(id: makeTabID(1), initialSurface: pane0)
        let pane1 = makeSurface(id: 2, path: "/p1")
        try tab.split(surface: pane0.id, adding: pane1, direction: .right)

        // Both halves are 0.8 x 1 (taller than wide) and tied on area;
        // the balanced target is pane0 (top-left tie-break), split
        // down -- unlike `attach(pane:)`, which would always add a
        // third outer column to the right instead.
        let pane2 = makeSurface(id: 3, path: "/p2")
        try tab.attachBalanced(pane: .surface(pane2), containerAspectRatio: 1.6)

        #expect(tab.paneIDs.count == 3)
        #expect(tab.focusedSurfaceID == pane2.id)
        #expect(tab.root.neighbor(of: pane0.id, in: .down) == pane2.id)
        #expect(tab.root.neighbor(of: pane1.id, in: .down) == nil)
    }

    @Test("attachBalanced rejects a node whose pane ID already exists in the tab")
    func attachBalancedRejectsDuplicates() throws {
        let surface = makeSurface(id: 1, path: "/repo")
        var tab = TabSession(id: makeTabID(1), initialSurface: surface)
        let before = tab

        #expect(throws: TabSessionError.duplicateSurface(surface.id)) {
            try tab.attachBalanced(pane: .surface(surface))
        }
        #expect(tab == before)
    }

    private func makeTabID(_ value: UInt8) -> TabID {
        TabID(rawValue: makeUUID(value))
    }

    private func makeSurface(
        id: UInt8,
        path: String
    ) -> TerminalSurfaceState {
        TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(id)),
            workingDirectory: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }
}
