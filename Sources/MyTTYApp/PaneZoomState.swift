import MyTTYCore

struct PaneZoomState {
    private var targetsByTab: [TabID: TerminalSurfaceID] = [:]

    @discardableResult
    mutating func toggle(for tab: TabSession) -> Bool {
        if targetsByTab.removeValue(forKey: tab.id) != nil {
            return false
        }
        guard tab.paneIDs.count > 1 else { return false }
        targetsByTab[tab.id] = tab.focusedSurfaceID
        return true
    }

    @discardableResult
    mutating func synchronize(with tab: TabSession) -> Bool {
        guard let previous = targetsByTab[tab.id] else { return false }
        if tab.paneIDs.count > 1 {
            targetsByTab[tab.id] = tab.focusedSurfaceID
        } else {
            targetsByTab.removeValue(forKey: tab.id)
        }
        return previous != targetsByTab[tab.id]
    }

    func target(for tab: TabSession) -> TerminalSurfaceID? {
        guard tab.paneIDs.count > 1,
              let target = targetsByTab[tab.id],
              tab.paneIDs.contains(target)
        else { return nil }
        return target
    }

    mutating func remove(tabID: TabID) {
        targetsByTab.removeValue(forKey: tabID)
    }
}
