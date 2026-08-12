import Foundation

public struct WindowID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct WindowFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WindowSession: Codable, Equatable, Sendable {
    public let id: WindowID
    public var frame: WindowFrame
    public private(set) var tabs: [TabSession]
    public private(set) var selectedTabID: TabID

    public var selectedTab: TabSession? {
        tabs.first { $0.id == selectedTabID }
    }

    public init(
        id: WindowID = WindowID(),
        frame: WindowFrame,
        tabs: [TabSession],
        selectedTabID: TabID
    ) {
        self.id = id
        self.frame = frame
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }

    public mutating func add(
        tab: TabSession,
        select: Bool
    ) throws {
        guard !tabs.contains(where: { $0.id == tab.id }) else {
            throw WindowSessionError.duplicateTab(tab.id)
        }
        tabs.append(tab)
        if select {
            selectedTabID = tab.id
        }
    }

    public mutating func select(tab id: TabID) throws {
        guard tabs.contains(where: { $0.id == id }) else {
            throw WindowSessionError.tabNotFound(id)
        }
        selectedTabID = id
    }

    public mutating func close(tab id: TabID) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            throw WindowSessionError.tabNotFound(id)
        }
        guard tabs.count > 1 else {
            throw WindowSessionError.cannotCloseLastTab
        }

        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    public mutating func move(tab id: TabID, to destinationIndex: Int) throws {
        guard tabs.indices.contains(destinationIndex) else {
            throw WindowSessionError.invalidTabIndex(destinationIndex)
        }
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else {
            throw WindowSessionError.tabNotFound(id)
        }
        guard sourceIndex != destinationIndex else { return }

        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
    }

    /// Removes a tab so it can move to another window. Unlike `close`,
    /// the last tab may be detached; the caller then owns closing the
    /// now-empty window, and `selectedTabID` keeps the detached ID.
    @discardableResult
    public mutating func detach(tab id: TabID) throws -> TabSession {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            throw WindowSessionError.tabNotFound(id)
        }

        let tab = tabs.remove(at: index)
        if selectedTabID == id, !tabs.isEmpty {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        return tab
    }

    public mutating func insert(
        tab: TabSession,
        at index: Int,
        select: Bool
    ) throws {
        guard !tabs.contains(where: { $0.id == tab.id }) else {
            throw WindowSessionError.duplicateTab(tab.id)
        }
        guard (tabs.startIndex...tabs.endIndex).contains(index) else {
            throw WindowSessionError.invalidTabIndex(index)
        }
        tabs.insert(tab, at: index)
        if select {
            selectedTabID = tab.id
        }
    }

    public mutating func rename(tab id: TabID, title: String?) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            throw WindowSessionError.tabNotFound(id)
        }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        tabs[index].pinnedTitle = title?.isEmpty == false ? title : nil
    }

    /// Sets the agent-derived automatic tab name. Unlike `rename(tab:title:)`
    /// this never throws for an unknown tab: the caller is a background
    /// suggestion task that races ordinary tab lifecycle (the tab may have
    /// closed by the time the model responds), and that race is routine,
    /// not an error worth surfacing.
    public mutating func setAutoTitle(tab id: TabID, title: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        tabs[index].autoTitle = title?.isEmpty == false ? title : nil
    }

    public mutating func updateWorkingDirectory(
        _ workingDirectory: URL,
        for surfaceID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.surfaceIDs.contains(surfaceID)
        }) else {
            throw WindowSessionError.surfaceNotFound(surfaceID)
        }

        var tab = tabs[index]
        try tab.updateWorkingDirectory(
            workingDirectory,
            for: surfaceID
        )
        tabs[index] = tab
    }

    public mutating func updateAgentResume(
        _ agentResume: AgentResumeDescriptor?,
        for surfaceID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.surfaceIDs.contains(surfaceID)
        }) else {
            throw WindowSessionError.surfaceNotFound(surfaceID)
        }

        var tab = tabs[index]
        try tab.updateAgentResume(agentResume, for: surfaceID)
        tabs[index] = tab
    }

    public mutating func updateTerminalHistory(
        _ terminalHistory: String?,
        for surfaceID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.surfaceIDs.contains(surfaceID)
        }) else {
            throw WindowSessionError.surfaceNotFound(surfaceID)
        }

        var tab = tabs[index]
        try tab.updateTerminalHistory(terminalHistory, for: surfaceID)
        tabs[index] = tab
    }

    public mutating func focus(
        surface surfaceID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.surfaceIDs.contains(surfaceID)
        }) else {
            throw WindowSessionError.surfaceNotFound(surfaceID)
        }

        var tab = tabs[index]
        try tab.focus(surface: surfaceID)
        tabs[index] = tab
        selectedTabID = tab.id
    }

    public mutating func focus(
        pane paneID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.paneIDs.contains(paneID)
        }) else {
            throw WindowSessionError.surfaceNotFound(paneID)
        }

        var tab = tabs[index]
        try tab.focus(surface: paneID)
        tabs[index] = tab
        selectedTabID = tab.id
    }

    public mutating func splitFocusedSurface(
        adding surface: TerminalSurfaceState,
        direction: SplitDirection
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.id == selectedTabID
        }) else { throw WindowSessionError.tabNotFound(selectedTabID) }
        var tab = tabs[index]
        try tab.split(
            surface: tab.focusedSurfaceID,
            adding: surface,
            direction: direction
        )
        tabs[index] = tab
    }

    /// Splits next to `targetID` (a terminal or browser pane) inside
    /// whichever tab contains it, without selecting that tab or moving its
    /// focus — the background counterpart of `splitFocusedSurface`, for
    /// orchestrated (agent/mytty-ctl) pane creation that must not steal
    /// the user's current tab or keyboard focus.
    public mutating func split(
        surface targetID: TerminalSurfaceID,
        adding newSurface: TerminalSurfaceState,
        direction: SplitDirection
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.paneIDs.contains(targetID)
        }) else { throw WindowSessionError.surfaceNotFound(targetID) }
        var tab = tabs[index]
        try tab.split(
            surface: targetID,
            adding: newSurface,
            direction: direction,
            focus: false
        )
        tabs[index] = tab
    }

    public mutating func splitOuterFocusedSurface(
        adding surface: TerminalSurfaceState,
        direction: SplitDirection
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.id == selectedTabID
        }) else { throw WindowSessionError.tabNotFound(selectedTabID) }
        var tab = tabs[index]
        try tab.splitOuter(adding: surface, direction: direction)
        tabs[index] = tab
    }

    public mutating func splitFocusedBrowser(
        adding browser: BrowserPaneState,
        direction: SplitDirection
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.id == selectedTabID
        }) else { throw WindowSessionError.tabNotFound(selectedTabID) }
        var tab = tabs[index]
        try tab.split(browser: browser, direction: direction)
        tabs[index] = tab
    }

    /// Records the title the host last reported for a remote pane, so a
    /// restored pane can name itself before its connection is back.
    public mutating func updateRemoteTitle(
        _ title: String,
        for paneID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.paneIDs.contains(paneID)
        }) else { throw WindowSessionError.surfaceNotFound(paneID) }
        var tab = tabs[index]
        try tab.updateRemoteTitle(title, for: paneID)
        tabs[index] = tab
    }

    public mutating func splitFocusedRemote(
        adding remote: RemotePaneState,
        direction: SplitDirection
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.id == selectedTabID
        }) else { throw WindowSessionError.tabNotFound(selectedTabID) }
        var tab = tabs[index]
        try tab.split(remote: remote, direction: direction)
        tabs[index] = tab
    }

    public mutating func closeSurface(
        _ surfaceID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.surfaceIDs.contains(surfaceID)
        }) else { throw WindowSessionError.surfaceNotFound(surfaceID) }
        var tab = tabs[index]
        try tab.close(surface: surfaceID)
        tabs[index] = tab
    }

    public mutating func closePane(
        _ paneID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.paneIDs.contains(paneID)
        }) else { throw WindowSessionError.surfaceNotFound(paneID) }
        var tab = tabs[index]
        try tab.close(pane: paneID)
        tabs[index] = tab
    }

    public mutating func swapPanes(
        _ firstID: TerminalSurfaceID,
        _ secondID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.paneIDs.contains(firstID)
        }) else { throw WindowSessionError.surfaceNotFound(firstID) }
        var tab = tabs[index]
        try tab.swapPanes(firstID, secondID)
        tabs[index] = tab
    }

    /// Moves a pane into another tab of this window. Moving a tab's
    /// sole pane removes the now-empty tab; when that tab was selected,
    /// the selection follows the pane to its destination.
    public mutating func movePane(
        _ paneID: TerminalSurfaceID,
        toTab destinationID: TabID
    ) throws {
        guard let sourceIndex = tabs.firstIndex(where: {
            $0.paneIDs.contains(paneID)
        }) else { throw WindowSessionError.surfaceNotFound(paneID) }
        guard tabs.contains(where: { $0.id == destinationID }) else {
            throw WindowSessionError.tabNotFound(destinationID)
        }
        let sourceID = tabs[sourceIndex].id
        guard sourceID != destinationID else { return }

        let node: SplitNode
        if tabs[sourceIndex].paneIDs.count == 1 {
            node = tabs[sourceIndex].root
            tabs.remove(at: sourceIndex)
            if selectedTabID == sourceID {
                selectedTabID = destinationID
            }
        } else {
            var source = tabs[sourceIndex]
            node = try source.detach(pane: paneID)
            tabs[sourceIndex] = source
        }

        guard let destinationIndex = tabs.firstIndex(where: {
            $0.id == destinationID
        }) else { throw WindowSessionError.tabNotFound(destinationID) }
        var destination = tabs[destinationIndex]
        try destination.attach(pane: node)
        tabs[destinationIndex] = destination
    }

    public mutating func updateBrowserURL(
        _ url: URL,
        for paneID: TerminalSurfaceID
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.root.browserState(with: paneID) != nil
        }) else { throw WindowSessionError.surfaceNotFound(paneID) }
        var tab = tabs[index]
        try tab.updateBrowserURL(url, for: paneID)
        tabs[index] = tab
    }

    @discardableResult
    public mutating func focusPane(in direction: SplitDirection) -> Bool {
        guard let index = tabs.firstIndex(where: {
            $0.id == selectedTabID
        }) else { return false }
        var tab = tabs[index]
        guard tab.focus(in: direction) else { return false }
        tabs[index] = tab
        return true
    }

    public mutating func updateSelectedSplitRatio(
        _ ratio: Double,
        at path: [SplitPathComponent]
    ) throws {
        guard let index = tabs.firstIndex(where: {
            $0.id == selectedTabID
        }) else { throw WindowSessionError.tabNotFound(selectedTabID) }
        var tab = tabs[index]
        try tab.updateSplitRatio(ratio, at: path)
        tabs[index] = tab
    }

    public mutating func equalizePanes(in tabID: TabID) throws {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            throw WindowSessionError.tabNotFound(tabID)
        }
        tabs[index].equalizePanes()
    }

    /// Moves `paneID` into this window's done tab for its containing
    /// tab (`mytty-ctl park` / `agent park`), creating that tab —
    /// pinned title, appended at the end of the tab strip, never
    /// selected — when none already matches
    /// `OrchestrationDoneTab.matches`. When an existing done tab is
    /// reused, the new pane lands at `TabSession.attachBalanced`'s
    /// placement rather than always the outer edge.
    ///
    /// Fails with `.alreadyParked` when `paneID` already lives in a
    /// done tab (`pinnedTitle` starts with
    /// `OrchestrationDoneTab.donePrefix`) — there's no "done of done".
    ///
    /// Mirrors `movePane`'s handling of a source tab's sole pane: the
    /// source tab is removed, and if it was selected, selection follows
    /// the pane to the done tab (the same fixup `movePane` performs —
    /// this never *initially* selects the done tab on creation).
    /// Returns the destination tab's ID.
    @discardableResult
    public mutating func parkPane(
        _ paneID: TerminalSurfaceID,
        parentTitle: String,
        containerAspectRatio: Double
    ) throws -> TabID {
        guard let sourceIndex = tabs.firstIndex(where: {
            $0.paneIDs.contains(paneID)
        }) else { throw WindowSessionError.surfaceNotFound(paneID) }

        let sourceTab = tabs[sourceIndex]
        guard !OrchestrationDoneTab.isDoneTitle(sourceTab.pinnedTitle) else {
            throw WindowSessionError.alreadyParked
        }

        let sourceTabID = sourceTab.id
        let doneTitle = OrchestrationDoneTab.title(
            parentTitle: parentTitle,
            parentTabID: sourceTabID
        )

        let node: SplitNode
        var sourceTabRemoved = false
        if sourceTab.paneIDs.count == 1 {
            node = sourceTab.root
            tabs.remove(at: sourceIndex)
            sourceTabRemoved = true
        } else {
            var source = sourceTab
            node = try source.detach(pane: paneID)
            tabs[sourceIndex] = source
        }

        let destinationID: TabID
        if let existingIndex = tabs.firstIndex(where: {
            OrchestrationDoneTab.matches(
                pinnedTitle: $0.pinnedTitle,
                parentTabID: sourceTabID
            )
        }) {
            var destination = tabs[existingIndex]
            try destination.attachBalanced(
                pane: node,
                containerAspectRatio: containerAspectRatio
            )
            tabs[existingIndex] = destination
            destinationID = destination.id
        } else {
            guard let firstPaneID = node.paneIDs.first else {
                throw WindowSessionError.surfaceNotFound(paneID)
            }
            let doneTab = TabSession(
                root: node,
                focusedSurfaceID: firstPaneID,
                pinnedTitle: doneTitle
            )
            try add(tab: doneTab, select: false)
            destinationID = doneTab.id
        }

        if sourceTabRemoved, selectedTabID == sourceTabID {
            selectedTabID = destinationID
        }
        return destinationID
    }
}

public enum WindowSessionError: Error, Equatable, Sendable {
    case tabNotFound(TabID)
    case duplicateTab(TabID)
    case invalidTabIndex(Int)
    case surfaceNotFound(TerminalSurfaceID)
    case cannotCloseLastTab
    /// `parkPane` was asked to park a pane that already lives in a done
    /// tab — see `OrchestrationDoneTab`.
    case alreadyParked
}

/// Naming and lookup for the "done" tab `WindowSession.parkPane` moves
/// finished orchestrated workers into, so a working tab full of live
/// panes doesn't accumulate finished ones. Kept separate from
/// `WindowSession.parkPane` so the naming rule is independently
/// testable and reusable (the app resolves the parent tab's display
/// title before calling `parkPane`, since that needs a localizer this
/// Foundation-only core layer doesn't have).
public enum OrchestrationDoneTab {
    /// Every done tab's `pinnedTitle` starts with this.
    public static let donePrefix = "done_"

    /// The parent-title portion is clamped to this many Unicode scalars
    /// so a hostile terminal-controlled tab title (an OSC title escape,
    /// ultimately) can't produce an absurd tab name.
    private static let maximumParentTitleScalars = 60

    /// `done_<parentTitle>_<id8>`, where `<id8>` is the first 8
    /// lowercase hex characters of `parentTabID` (hyphens removed) and
    /// `<parentTitle>` is clamped/sanitized — see `clampedParentTitle`.
    public static func title(
        parentTitle: String,
        parentTabID: TabID
    ) -> String {
        "\(donePrefix)\(clampedParentTitle(parentTitle))_"
            + idSuffix(for: parentTabID)
    }

    /// True when `pinnedTitle` is an existing done tab *for
    /// `parentTabID` specifically* — found by suffix rather than a full
    /// name match, since the parent tab's display title (embedded in
    /// the middle of the done tab's name) may have changed since the
    /// done tab was created.
    public static func matches(
        pinnedTitle: String?,
        parentTabID: TabID
    ) -> Bool {
        guard let pinnedTitle, isDoneTitle(pinnedTitle) else { return false }
        return pinnedTitle.hasSuffix("_\(idSuffix(for: parentTabID))")
    }

    /// True for any done tab, regardless of which parent it belongs to
    /// — used to reject parking a pane that's already parked (no "done
    /// of done").
    public static func isDoneTitle(_ pinnedTitle: String?) -> Bool {
        pinnedTitle?.hasPrefix(donePrefix) == true
    }

    private static func idSuffix(for tabID: TabID) -> String {
        String(
            tabID.rawValue.uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
                .prefix(8)
        )
    }

    private static func clampedParentTitle(_ title: String) -> String {
        let scalars = title.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        return String(
            String.UnicodeScalarView(scalars.prefix(maximumParentTitleScalars))
        )
    }
}

public struct SessionSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var windows: [WindowSession]
    public var lastWindowFrame: WindowFrame?

    public init(
        windows: [WindowSession],
        lastWindowFrame: WindowFrame? = nil
    ) {
        self.windows = windows
        self.lastWindowFrame = lastWindowFrame
    }
}
