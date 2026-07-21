import Foundation

public struct TabID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct TerminalSurfaceID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }
}

public enum AgentResumeKind: String, Codable, Equatable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case openCode = "opencode"
    case gemini
    case antigravity
    case cursor
}

public struct AgentResumeDescriptor: Codable, Equatable, Sendable {
    public let kind: AgentResumeKind
    public let sessionID: String

    public init(kind: AgentResumeKind, sessionID: String) {
        self.kind = kind
        self.sessionID = sessionID
    }
}

public struct TerminalSurfaceState: Codable, Equatable, Sendable {
    public let id: TerminalSurfaceID
    public var workingDirectory: URL
    public var agentResume: AgentResumeDescriptor?
    /// Scrollback encoded as VT/ANSI text so visual attributes can be replayed.
    public var terminalHistory: String?

    public init(
        id: TerminalSurfaceID = TerminalSurfaceID(),
        workingDirectory: URL,
        agentResume: AgentResumeDescriptor? = nil,
        terminalHistory: String? = nil
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.agentResume = agentResume
        self.terminalHistory = terminalHistory
    }
}

public struct BrowserPaneState: Codable, Equatable, Sendable {
    public let id: TerminalSurfaceID
    public var url: URL

    public init(
        id: TerminalSurfaceID = TerminalSurfaceID(),
        url: URL
    ) {
        self.id = id
        self.url = url
    }
}

public enum SplitOrientation: String, Codable, Equatable, Sendable {
    case horizontal
    case vertical
}

public enum SplitDirection: String, Codable, Equatable, Sendable {
    case left
    case right
    case up
    case down
}

public enum SplitPathComponent: String, Codable, Equatable, Sendable {
    case first
    case second
}

public indirect enum SplitNode: Codable, Equatable, Sendable {
    case surface(TerminalSurfaceState)
    case browser(BrowserPaneState)
    case split(
        orientation: SplitOrientation,
        ratio: Double,
        first: SplitNode,
        second: SplitNode
    )

    public var surfaceIDs: [TerminalSurfaceID] {
        switch self {
        case let .surface(surface):
            [surface.id]
        case .browser:
            []
        case let .split(_, _, first, second):
            first.surfaceIDs + second.surfaceIDs
        }
    }

    public var paneIDs: [TerminalSurfaceID] {
        switch self {
        case let .surface(surface):
            [surface.id]
        case let .browser(browser):
            [browser.id]
        case let .split(_, _, first, second):
            first.paneIDs + second.paneIDs
        }
    }

    public func browserState(
        with id: TerminalSurfaceID
    ) -> BrowserPaneState? {
        switch self {
        case .surface:
            nil
        case let .browser(browser):
            browser.id == id ? browser : nil
        case let .split(_, _, first, second):
            first.browserState(with: id) ?? second.browserState(with: id)
        }
    }

    fileprivate func contains(_ id: TerminalSurfaceID) -> Bool {
        switch self {
        case let .surface(surface):
            surface.id == id
        case let .browser(browser):
            browser.id == id
        case let .split(_, _, first, second):
            first.contains(id) || second.contains(id)
        }
    }

    fileprivate func leaf(for id: TerminalSurfaceID) -> SplitNode? {
        switch self {
        case let .surface(surface):
            return surface.id == id ? self : nil
        case let .browser(browser):
            return browser.id == id ? self : nil
        case let .split(_, _, first, second):
            return first.leaf(for: id) ?? second.leaf(for: id)
        }
    }

    fileprivate func swapping(
        _ firstID: TerminalSurfaceID,
        with firstReplacement: SplitNode,
        _ secondID: TerminalSurfaceID,
        with secondReplacement: SplitNode
    ) -> SplitNode {
        switch self {
        case let .surface(surface):
            if surface.id == firstID { return firstReplacement }
            if surface.id == secondID { return secondReplacement }
            return self
        case let .browser(browser):
            if browser.id == firstID { return firstReplacement }
            if browser.id == secondID { return secondReplacement }
            return self
        case let .split(orientation, ratio, first, second):
            return .split(
                orientation: orientation,
                ratio: ratio,
                first: first.swapping(
                    firstID,
                    with: firstReplacement,
                    secondID,
                    with: secondReplacement
                ),
                second: second.swapping(
                    firstID,
                    with: firstReplacement,
                    secondID,
                    with: secondReplacement
                )
            )
        }
    }

    fileprivate func replacing(
        pane id: TerminalSurfaceID,
        with transform: (SplitNode) -> SplitNode
    ) -> SplitNode? {
        switch self {
        case let .surface(surface):
            guard surface.id == id else { return nil }
            return transform(self)
        case let .browser(browser):
            guard browser.id == id else { return nil }
            return transform(self)
        case let .split(orientation, ratio, first, second):
            if let replacement = first.replacing(pane: id, with: transform) {
                return .split(
                    orientation: orientation,
                    ratio: ratio,
                    first: replacement,
                    second: second
                )
            }
            if let replacement = second.replacing(pane: id, with: transform) {
                return .split(
                    orientation: orientation,
                    ratio: ratio,
                    first: first,
                    second: replacement
                )
            }
            return nil
        }
    }

    fileprivate func replacing(
        surface id: TerminalSurfaceID,
        with transform: (TerminalSurfaceState) -> SplitNode
    ) -> SplitNode? {
        switch self {
        case let .surface(surface):
            guard surface.id == id else { return nil }
            return transform(surface)

        case .browser:
            return nil

        case let .split(orientation, ratio, first, second):
            if let replacement = first.replacing(
                surface: id,
                with: transform
            ) {
                return .split(
                    orientation: orientation,
                    ratio: ratio,
                    first: replacement,
                    second: second
                )
            }
            if let replacement = second.replacing(
                surface: id,
                with: transform
            ) {
                return .split(
                    orientation: orientation,
                    ratio: ratio,
                    first: first,
                    second: replacement
                )
            }
            return nil
        }
    }

    fileprivate func removing(
        surface id: TerminalSurfaceID
    ) -> SplitRemoval? {
        switch self {
        case let .surface(surface):
            guard surface.id == id else { return nil }
            return SplitRemoval(node: nil, focusCandidate: nil)

        case let .browser(browser):
            guard browser.id == id else { return nil }
            return SplitRemoval(node: nil, focusCandidate: nil)

        case let .split(orientation, ratio, first, second):
            if let removal = first.removing(surface: id) {
                guard let remaining = removal.node else {
                    return SplitRemoval(
                        node: second,
                        focusCandidate: second.paneIDs.first
                    )
                }
                return SplitRemoval(
                    node: .split(
                        orientation: orientation,
                        ratio: ratio,
                        first: remaining,
                        second: second
                    ),
                    focusCandidate: removal.focusCandidate
                )
            }

            if let removal = second.removing(surface: id) {
                guard let remaining = removal.node else {
                    return SplitRemoval(
                        node: first,
                        focusCandidate: first.paneIDs.first
                    )
                }
                return SplitRemoval(
                    node: .split(
                        orientation: orientation,
                        ratio: ratio,
                        first: first,
                        second: remaining
                    ),
                    focusCandidate: removal.focusCandidate
                )
            }

            return nil
        }
    }

    fileprivate func updatingSplitRatio(
        _ ratio: Double,
        at path: ArraySlice<SplitPathComponent>
    ) -> SplitNode? {
        guard case let .split(orientation, currentRatio, first, second) = self
        else { return nil }
        guard let component = path.first else {
            return .split(
                orientation: orientation,
                ratio: ratio,
                first: first,
                second: second
            )
        }

        switch component {
        case .first:
            guard let updated = first.updatingSplitRatio(
                ratio,
                at: path.dropFirst()
            ) else { return nil }
            return .split(
                orientation: orientation,
                ratio: currentRatio,
                first: updated,
                second: second
            )
        case .second:
            guard let updated = second.updatingSplitRatio(
                ratio,
                at: path.dropFirst()
            ) else { return nil }
            return .split(
                orientation: orientation,
                ratio: currentRatio,
                first: first,
                second: updated
            )
        }
    }

    fileprivate func equalized() -> SplitNode {
        switch self {
        case .surface, .browser:
            return self
        case let .split(orientation, _, first, second):
            let firstWeight = first.weight(for: orientation)
            let secondWeight = second.weight(for: orientation)
            return .split(
                orientation: orientation,
                ratio: Double(firstWeight)
                    / Double(firstWeight + secondWeight),
                first: first.equalized(),
                second: second.equalized()
            )
        }
    }

    private func weight(for orientation: SplitOrientation) -> Int {
        switch self {
        case .surface, .browser:
            return 1
        case let .split(nodeOrientation, _, first, second):
            guard nodeOrientation == orientation else { return 1 }
            return first.weight(for: orientation)
                + second.weight(for: orientation)
        }
    }

    public func neighbor(
        of surfaceID: TerminalSurfaceID,
        in direction: SplitDirection
    ) -> TerminalSurfaceID? {
        let panes = paneFrames(in: PaneFrame(x: 0, y: 0, width: 1, height: 1))
        guard let target = panes.first(where: { $0.id == surfaceID }) else {
            return nil
        }

        return panes
            .filter { $0.id != surfaceID }
            .compactMap { candidate -> (TerminalSurfaceID, Double, Double)? in
                let gap: Double
                let orthogonalDistance: Double
                switch direction {
                case .left:
                    guard candidate.frame.maxX <= target.frame.minX + 0.0001,
                          candidate.frame.verticalOverlap(with: target.frame) > 0
                    else { return nil }
                    gap = target.frame.minX - candidate.frame.maxX
                    orthogonalDistance = abs(
                        target.frame.midY - candidate.frame.midY
                    )
                case .right:
                    guard candidate.frame.minX >= target.frame.maxX - 0.0001,
                          candidate.frame.verticalOverlap(with: target.frame) > 0
                    else { return nil }
                    gap = candidate.frame.minX - target.frame.maxX
                    orthogonalDistance = abs(
                        target.frame.midY - candidate.frame.midY
                    )
                case .up:
                    guard candidate.frame.maxY <= target.frame.minY + 0.0001,
                          candidate.frame.horizontalOverlap(with: target.frame) > 0
                    else { return nil }
                    gap = target.frame.minY - candidate.frame.maxY
                    orthogonalDistance = abs(
                        target.frame.midX - candidate.frame.midX
                    )
                case .down:
                    guard candidate.frame.minY >= target.frame.maxY - 0.0001,
                          candidate.frame.horizontalOverlap(with: target.frame) > 0
                    else { return nil }
                    gap = candidate.frame.minY - target.frame.maxY
                    orthogonalDistance = abs(
                        target.frame.midX - candidate.frame.midX
                    )
                }
                return (candidate.id, max(0, gap), orthogonalDistance)
            }
            .min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.2 < rhs.2
            }?.0
    }

    private func paneFrames(in frame: PaneFrame) -> [PaneLayout] {
        switch self {
        case let .surface(surface):
            return [PaneLayout(id: surface.id, frame: frame)]
        case let .browser(browser):
            return [PaneLayout(id: browser.id, frame: frame)]
        case let .split(orientation, ratio, first, second):
            switch orientation {
            case .horizontal:
                let firstWidth = frame.width * ratio
                return first.paneFrames(
                    in: PaneFrame(
                        x: frame.x,
                        y: frame.y,
                        width: firstWidth,
                        height: frame.height
                    )
                ) + second.paneFrames(
                    in: PaneFrame(
                        x: frame.x + firstWidth,
                        y: frame.y,
                        width: frame.width - firstWidth,
                        height: frame.height
                    )
                )
            case .vertical:
                let firstHeight = frame.height * ratio
                return first.paneFrames(
                    in: PaneFrame(
                        x: frame.x,
                        y: frame.y,
                        width: frame.width,
                        height: firstHeight
                    )
                ) + second.paneFrames(
                    in: PaneFrame(
                        x: frame.x,
                        y: frame.y + firstHeight,
                        width: frame.width,
                        height: frame.height - firstHeight
                    )
                )
            }
        }
    }
}

public enum TabSessionError: Error, Equatable, Sendable {
    case surfaceNotFound(TerminalSurfaceID)
    case duplicateSurface(TerminalSurfaceID)
    case cannotCloseLastSurface
    case splitNotFound
    case invalidSplitRatio
}

public struct TabSession: Codable, Equatable, Sendable {
    public let id: TabID
    public private(set) var root: SplitNode
    public private(set) var focusedSurfaceID: TerminalSurfaceID
    public var pinnedTitle: String?

    public var surfaceIDs: [TerminalSurfaceID] {
        root.surfaceIDs
    }

    public var paneIDs: [TerminalSurfaceID] {
        root.paneIDs
    }

    public init(
        id: TabID = TabID(),
        initialSurface: TerminalSurfaceState,
        pinnedTitle: String? = nil
    ) {
        self.id = id
        self.root = .surface(initialSurface)
        self.focusedSurfaceID = initialSurface.id
        self.pinnedTitle = pinnedTitle
    }

    public init(
        id: TabID = TabID(),
        initialBrowser: BrowserPaneState,
        pinnedTitle: String? = nil
    ) {
        self.id = id
        self.root = .browser(initialBrowser)
        self.focusedSurfaceID = initialBrowser.id
        self.pinnedTitle = pinnedTitle
    }

    public init(
        id: TabID = TabID(),
        root: SplitNode,
        focusedSurfaceID: TerminalSurfaceID,
        pinnedTitle: String? = nil
    ) {
        self.id = id
        self.root = root
        self.focusedSurfaceID = focusedSurfaceID
        self.pinnedTitle = pinnedTitle
    }

    public mutating func focus(surface id: TerminalSurfaceID) throws {
        guard root.contains(id) else {
            throw TabSessionError.surfaceNotFound(id)
        }
        focusedSurfaceID = id
    }

    @discardableResult
    public mutating func focus(in direction: SplitDirection) -> Bool {
        guard let neighbor = root.neighbor(
            of: focusedSurfaceID,
            in: direction
        ) else { return false }
        focusedSurfaceID = neighbor
        return true
    }

    /// Looks up the neighboring pane in a direction without changing
    /// `focusedSurfaceID`, for callers that track their own cursor (e.g. a
    /// pane picker driven by arrow keys instead of real terminal focus).
    public func neighborPane(
        of paneID: TerminalSurfaceID,
        in direction: SplitDirection
    ) -> TerminalSurfaceID? {
        root.neighbor(of: paneID, in: direction)
    }

    public mutating func split(
        surface targetID: TerminalSurfaceID,
        adding newSurface: TerminalSurfaceState,
        direction: SplitDirection
    ) throws {
        try split(
            pane: targetID,
            adding: .surface(newSurface),
            id: newSurface.id,
            direction: direction
        )
    }

    public mutating func split(
        browser: BrowserPaneState,
        direction: SplitDirection
    ) throws {
        try split(
            pane: focusedSurfaceID,
            adding: .browser(browser),
            id: browser.id,
            direction: direction
        )
    }

    private mutating func split(
        pane targetID: TerminalSurfaceID,
        adding newNode: SplitNode,
        id newID: TerminalSurfaceID,
        direction: SplitDirection
    ) throws {
        guard root.contains(targetID) else {
            throw TabSessionError.surfaceNotFound(targetID)
        }
        guard !root.contains(newID) else {
            throw TabSessionError.duplicateSurface(newID)
        }

        let replacement = root.replacing(pane: targetID) { targetNode in
            let orientation: SplitOrientation
            let first: SplitNode
            let second: SplitNode

            switch direction {
            case .left:
                orientation = .horizontal
                first = newNode
                second = targetNode
            case .right:
                orientation = .horizontal
                first = targetNode
                second = newNode
            case .up:
                orientation = .vertical
                first = newNode
                second = targetNode
            case .down:
                orientation = .vertical
                first = targetNode
                second = newNode
            }

            return .split(
                orientation: orientation,
                ratio: 0.5,
                first: first,
                second: second
            )
        }

        guard let replacement else {
            throw TabSessionError.surfaceNotFound(targetID)
        }
        root = replacement
        focusedSurfaceID = newID
    }

    public mutating func close(surface id: TerminalSurfaceID) throws {
        try close(pane: id)
    }

    public mutating func close(pane id: TerminalSurfaceID) throws {
        guard root.contains(id) else {
            throw TabSessionError.surfaceNotFound(id)
        }
        guard paneIDs.count > 1 else {
            throw TabSessionError.cannotCloseLastSurface
        }
        guard let removal = root.removing(surface: id),
              let remaining = removal.node
        else {
            throw TabSessionError.surfaceNotFound(id)
        }

        root = remaining
        if focusedSurfaceID == id,
           let focusCandidate = removal.focusCandidate {
            focusedSurfaceID = focusCandidate
        }
    }

    public mutating func swapPanes(
        _ firstID: TerminalSurfaceID,
        _ secondID: TerminalSurfaceID
    ) throws {
        guard root.contains(firstID) else {
            throw TabSessionError.surfaceNotFound(firstID)
        }
        guard root.contains(secondID) else {
            throw TabSessionError.surfaceNotFound(secondID)
        }
        guard firstID != secondID else { return }

        guard let firstNode = root.leaf(for: firstID),
              let secondNode = root.leaf(for: secondID)
        else {
            throw TabSessionError.surfaceNotFound(firstID)
        }

        root = root.swapping(
            firstID,
            with: secondNode,
            secondID,
            with: firstNode
        )
    }

    public mutating func updateBrowserURL(
        _ url: URL,
        for id: TerminalSurfaceID
    ) throws {
        guard let replacement = root.replacing(pane: id, with: { node in
            guard case var .browser(browser) = node else { return node }
            browser.url = url
            return .browser(browser)
        }), root.browserState(with: id) != nil else {
            throw TabSessionError.surfaceNotFound(id)
        }
        root = replacement
    }

    public mutating func updateWorkingDirectory(
        _ workingDirectory: URL,
        for id: TerminalSurfaceID
    ) throws {
        guard let replacement = root.replacing(surface: id, with: { surface in
            var updated = surface
            updated.workingDirectory = workingDirectory
            return .surface(updated)
        }) else {
            throw TabSessionError.surfaceNotFound(id)
        }
        root = replacement
    }

    public mutating func updateAgentResume(
        _ agentResume: AgentResumeDescriptor?,
        for id: TerminalSurfaceID
    ) throws {
        guard let replacement = root.replacing(surface: id, with: { surface in
            var updated = surface
            updated.agentResume = agentResume
            return .surface(updated)
        }) else {
            throw TabSessionError.surfaceNotFound(id)
        }
        root = replacement
    }

    public mutating func updateTerminalHistory(
        _ terminalHistory: String?,
        for id: TerminalSurfaceID
    ) throws {
        guard let replacement = root.replacing(surface: id, with: { surface in
            var updated = surface
            updated.terminalHistory = terminalHistory
            return .surface(updated)
        }) else {
            throw TabSessionError.surfaceNotFound(id)
        }
        root = replacement
    }

    public mutating func updateSplitRatio(
        _ ratio: Double,
        at path: [SplitPathComponent]
    ) throws {
        guard ratio.isFinite, (0.05...0.95).contains(ratio) else {
            throw TabSessionError.invalidSplitRatio
        }
        guard let updated = root.updatingSplitRatio(
            ratio,
            at: path[...]
        ) else { throw TabSessionError.splitNotFound }
        root = updated
    }

    public mutating func equalizePanes() {
        root = root.equalized()
    }
}

private struct SplitRemoval {
    let node: SplitNode?
    let focusCandidate: TerminalSurfaceID?
}

private struct PaneLayout {
    let id: TerminalSurfaceID
    let frame: PaneFrame
}

private struct PaneFrame {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var minX: Double { x }
    var maxX: Double { x + width }
    var midX: Double { x + width / 2 }
    var minY: Double { y }
    var maxY: Double { y + height }
    var midY: Double { y + height / 2 }

    func horizontalOverlap(with other: PaneFrame) -> Double {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }

    func verticalOverlap(with other: PaneFrame) -> Double {
        max(0, min(maxY, other.maxY) - max(minY, other.minY))
    }
}
