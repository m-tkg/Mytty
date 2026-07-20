import Foundation
import MyTTYCore

enum PaneListItemKind: Equatable {
    case terminal
    case browser
}

struct PaneListItem: Identifiable, Equatable {
    struct ID: Hashable {
        let windowID: WindowID
        let paneID: TerminalSurfaceID
    }

    let windowID: WindowID
    let tabID: TabID
    let paneID: TerminalSurfaceID
    let tabTitle: String
    let command: String
    let location: String
    let kind: PaneListItemKind
    let isActive: Bool

    var id: ID {
        ID(windowID: windowID, paneID: paneID)
    }
}

struct PaneListWindowSnapshot {
    let session: WindowSession
    let commandsByPane: [TerminalSurfaceID: String]
}

enum PaneListPresentation {
    static func commandName(
        executableName: String?,
        provider: AgentProvider?
    ) -> String? {
        if let provider {
            return TerminalWindowTitle.name(for: provider)
        }
        return executableName
    }

    static func items(
        snapshots: [PaneListWindowSnapshot],
        terminalTitle: String,
        browserTitle: String,
        localizer: MyTTYLocalizer
    ) -> [PaneListItem] {
        snapshots.flatMap { snapshot in
            snapshot.session.tabs.flatMap { tab in
                tab.paneIDs.compactMap { paneID in
                    makeItem(
                        paneID: paneID,
                        tab: tab,
                        snapshot: snapshot,
                        terminalTitle: terminalTitle,
                        browserTitle: browserTitle,
                        localizer: localizer
                    )
                }
            }
        }
    }

    private static func makeItem(
        paneID: TerminalSurfaceID,
        tab: TabSession,
        snapshot: PaneListWindowSnapshot,
        terminalTitle: String,
        browserTitle: String,
        localizer: MyTTYLocalizer
    ) -> PaneListItem? {
        let isActive = snapshot.session.selectedTabID == tab.id
            && tab.focusedSurfaceID == paneID
        let tabTitle = tab.pinnedTitle
            ?? TerminalTabTitle.defaultTitle(for: tab, localizer: localizer)

        if let terminal = terminalState(in: tab.root, id: paneID) {
            return PaneListItem(
                windowID: snapshot.session.id,
                tabID: tab.id,
                paneID: paneID,
                tabTitle: tabTitle,
                command: snapshot.commandsByPane[paneID] ?? terminalTitle,
                location: terminal.workingDirectory.path,
                kind: .terminal,
                isActive: isActive
            )
        }
        if let browser = tab.root.browserState(with: paneID) {
            return PaneListItem(
                windowID: snapshot.session.id,
                tabID: tab.id,
                paneID: paneID,
                tabTitle: tabTitle,
                command: browserTitle,
                location: browser.url.absoluteString,
                kind: .browser,
                isActive: isActive
            )
        }
        return nil
    }

    private static func terminalState(
        in node: SplitNode,
        id: TerminalSurfaceID
    ) -> TerminalSurfaceState? {
        switch node {
        case let .surface(state):
            state.id == id ? state : nil
        case .browser:
            nil
        case let .split(_, _, first, second):
            terminalState(in: first, id: id)
                ?? terminalState(in: second, id: id)
        }
    }
}
