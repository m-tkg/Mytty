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
    /// True when this pane was created through the mytty-ctl control surface
    /// by an orchestrating agent; attention notifications for it are
    /// suppressed because the orchestrator handles its approvals/results.
    public var isOrchestrated: Bool

    public init(
        id: TerminalSurfaceID = TerminalSurfaceID(),
        workingDirectory: URL,
        agentResume: AgentResumeDescriptor? = nil,
        terminalHistory: String? = nil,
        isOrchestrated: Bool = false
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.agentResume = agentResume
        self.terminalHistory = terminalHistory
        self.isOrchestrated = isOrchestrated
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case workingDirectory
        case agentResume
        case terminalHistory
        case isOrchestrated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TerminalSurfaceID.self, forKey: .id)
        workingDirectory = try container.decode(URL.self, forKey: .workingDirectory)
        agentResume = try container.decodeIfPresent(
            AgentResumeDescriptor.self,
            forKey: .agentResume
        )
        terminalHistory = try container.decodeIfPresent(
            String.self,
            forKey: .terminalHistory
        )
        isOrchestrated = try container.decodeIfPresent(
            Bool.self,
            forKey: .isOrchestrated
        ) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workingDirectory, forKey: .workingDirectory)
        try container.encodeIfPresent(agentResume, forKey: .agentResume)
        try container.encodeIfPresent(terminalHistory, forKey: .terminalHistory)
        try container.encode(isOrchestrated, forKey: .isOrchestrated)
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

/// A pane mirroring a terminal that lives on another Mac. It has no local
/// process, working directory or Ghostty surface — everything it shows
/// arrives over the remote protocol — which is why it is a pane kind of its
/// own rather than a terminal with a different command. Local-only concerns
/// (agent status polling, repository status, mytty-ctl addressing) all skip
/// this kind deliberately.
public struct RemotePaneState: Codable, Equatable, Sendable {
    public let id: TerminalSurfaceID
    /// The paired Mac this pane mirrors, as recorded by `RemoteHostStore`.
    public var hostID: String
    /// The pane's ID *on that Mac*. The remote window and tab are not
    /// stored: the host rearranges its own layout freely, and every
    /// protocol message is addressed by pane ID alone.
    public var remotePaneID: String
    /// The host's display label, kept locally so a restored pane can name
    /// itself before the connection is back.
    public var hostName: String
    /// The pane title last seen on the host, for the same reason.
    public var title: String

    public init(
        id: TerminalSurfaceID = TerminalSurfaceID(),
        hostID: String,
        remotePaneID: String,
        hostName: String,
        title: String
    ) {
        self.id = id
        self.hostID = hostID
        self.remotePaneID = remotePaneID
        self.hostName = hostName
        self.title = title
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

/// Where a split inserts the new pane: next to the target pane, or at the
/// outer edge of the whole tab layout.
public enum SplitPlacement: String, Codable, Equatable, Sendable {
    case adjacent
    case outer
}

public enum SplitPathComponent: String, Codable, Equatable, Sendable {
    case first
    case second
}

public indirect enum SplitNode: Codable, Equatable, Sendable {
    case surface(TerminalSurfaceState)
    case browser(BrowserPaneState)
    case remote(RemotePaneState)
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
        case .browser, .remote:
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
        case let .remote(remote):
            [remote.id]
        case let .split(_, _, first, second):
            first.paneIDs + second.paneIDs
        }
    }

    public func browserState(
        with id: TerminalSurfaceID
    ) -> BrowserPaneState? {
        switch self {
        case .surface, .remote:
            nil
        case let .browser(browser):
            browser.id == id ? browser : nil
        case let .split(_, _, first, second):
            first.browserState(with: id) ?? second.browserState(with: id)
        }
    }

    public func remoteState(
        with id: TerminalSurfaceID
    ) -> RemotePaneState? {
        switch self {
        case .surface, .browser:
            nil
        case let .remote(remote):
            remote.id == id ? remote : nil
        case let .split(_, _, first, second):
            first.remoteState(with: id) ?? second.remoteState(with: id)
        }
    }

    fileprivate func contains(_ id: TerminalSurfaceID) -> Bool {
        switch self {
        case let .surface(surface):
            surface.id == id
        case let .browser(browser):
            browser.id == id
        case let .remote(remote):
            remote.id == id
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
        case let .remote(remote):
            return remote.id == id ? self : nil
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
        case let .remote(remote):
            if remote.id == firstID { return firstReplacement }
            if remote.id == secondID { return secondReplacement }
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
        case let .remote(remote):
            guard remote.id == id else { return nil }
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

        case .browser, .remote:
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

        case let .remote(remote):
            guard remote.id == id else { return nil }
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
        case .surface, .browser, .remote:
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
        case .surface, .browser, .remote:
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
        case let .remote(remote):
            return [PaneLayout(id: remote.id, frame: frame)]
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

extension SplitNode {
    /// Exposes `paneFrames(in:)` to `BalancedPaneInsertion` without
    /// widening that method's own access beyond `private` — this
    /// extension can see it because it's declared in the same file.
    fileprivate func balancedPaneFrames(
        containerAspectRatio: Double
    ) -> [PaneLayout] {
        paneFrames(in: PaneFrame(
            x: 0,
            y: 0,
            width: containerAspectRatio,
            height: 1
        ))
    }

    /// The frames that would result from splitting `targetID` in
    /// `direction`, without actually mutating any real pane state — a
    /// throwaway placeholder surface stands in for the pane the split
    /// would add. Used only by `BalancedPaneInsertion.target`'s
    /// row-balance tie-break, to score candidates before committing to
    /// one. `nil` when `targetID` isn't in this tree.
    fileprivate func simulatedFrames(
        splitting targetID: TerminalSurfaceID,
        direction: SplitDirection,
        containerAspectRatio: Double
    ) -> [PaneLayout]? {
        let placeholder = SplitNode.surface(
            TerminalSurfaceState(
                workingDirectory: URL(fileURLWithPath: "/", isDirectory: true)
            )
        )
        let transform: (SplitNode) -> SplitNode = { targetNode in
            TabSession.wrapped(
                targetNode,
                adding: placeholder,
                direction: direction
            )
        }
        guard let simulatedRoot = replacing(pane: targetID, with: transform)
        else { return nil }
        return simulatedRoot.balancedPaneFrames(
            containerAspectRatio: containerAspectRatio
        )
    }
}

/// Balanced (near-square) pane placement for orchestrated worker spawns.
/// `mytty-ctl split --direction auto` and `agent spawn` (with
/// `--direction` omitted, which defaults to `auto`) resolve through this
/// instead of always growing a 1×N strip to the right.
public enum BalancedPaneInsertion {
    /// A typical macOS terminal window is noticeably wider than tall;
    /// used when a caller can't measure its real container (or for any
    /// test that doesn't care about a specific window shape).
    public static let defaultContainerAspectRatio = 1.6

    /// Picks which existing pane leaf to split, and in which direction,
    /// so inserting a new pane there keeps the whole layout close to an
    /// evenly filled grid.
    ///
    /// The rule: scale every leaf's frame into a container of width
    /// `containerAspectRatio` and height `1` (matching the tab's actual
    /// proportions, so a wide window fills columns before rows), and
    /// pick the pane with the largest area to split along its *longer*
    /// effective side: width ≥ height picks `.right`, otherwise
    /// `.down`. Splitting the largest pane along its long axis is a
    /// simple greedy rule that, applied repeatedly from a single pane,
    /// converges toward near-square grids that fill horizontally first
    /// for the wide aspect ratios real windows have.
    ///
    /// Ties on area (within a small relative epsilon) don't fall
    /// straight to a positional rule: each tied candidate is simulated
    /// (split along its own longer side) and the *resulting* layout is
    /// scored by row balance -- panes are clustered into rows by
    /// vertical-overlap (`rowGroups`), and the candidate minimizing
    /// `maxRowCount - minRowCount` wins, so a fork that would leave one
    /// row much fuller than another loses to one that keeps rows even.
    /// This is what turns a 5-pane top-3/bottom-2 layout into a proper
    /// 3-column x 2-row grid at 6 panes instead of a 4-top/2-bottom
    /// split, at the aspect ratios real windows have. Only after that
    /// tie-break also ties does position decide: the top-left-most
    /// candidate (smallest `y`, then smallest `x`) for determinism.
    ///
    /// Candidates are restricted to terminal-surface leaves
    /// (`SplitNode.surface`) whenever the tab has at least one, so an
    /// orchestrated split never lands next to a browser/remote pane
    /// when a terminal target is available; a tab with only
    /// browser/remote panes falls back to any leaf so this still
    /// returns a target. Returns `nil` only for an empty tree, which
    /// shouldn't occur for a real `TabSession` (always at least one
    /// pane) — callers should fall back to a fixed direction in that
    /// case.
    public static func target(
        in root: SplitNode,
        containerAspectRatio: Double = defaultContainerAspectRatio
    ) -> (paneID: TerminalSurfaceID, direction: SplitDirection)? {
        let aspect = normalizedAspectRatio(containerAspectRatio)
        let frames = root.balancedPaneFrames(containerAspectRatio: aspect)
        guard !frames.isEmpty else { return nil }

        let terminalIDs = Set(root.surfaceIDs)
        let candidates = terminalIDs.isEmpty
            ? frames
            : frames.filter { terminalIDs.contains($0.id) }
        let pool = candidates.isEmpty ? frames : candidates

        guard let maxArea = pool
            .map({ $0.frame.width * $0.frame.height })
            .max()
        else { return nil }
        let epsilon = max(1e-9, abs(maxArea) * 1e-9)
        let tiedOnArea = pool.filter {
            abs($0.frame.width * $0.frame.height - maxArea) <= epsilon
        }
        // Deterministic base ordering for every subsequent tie-break:
        // top-left-most first.
        let ordered = tiedOnArea.sorted { lhs, rhs in
            if lhs.frame.y != rhs.frame.y { return lhs.frame.y < rhs.frame.y }
            return lhs.frame.x < rhs.frame.x
        }

        guard ordered.count > 1 else {
            let chosen = ordered[0]
            return (chosen.id, direction(for: chosen.frame))
        }

        var best: PaneLayout?
        var bestScore = Int.max
        for candidate in ordered {
            let candidateDirection = direction(for: candidate.frame)
            guard let simulated = root.simulatedFrames(
                splitting: candidate.id,
                direction: candidateDirection,
                containerAspectRatio: aspect
            ) else { continue }
            let counts = rowGroups(from: simulated).map(\.count)
            guard let maxCount = counts.max(),
                  let minCount = counts.min()
            else { continue }
            let score = maxCount - minCount
            // Strict `<` only: `ordered` is already top-left-first, so
            // the first candidate to reach a given score keeps it.
            if score < bestScore {
                bestScore = score
                best = candidate
            }
        }

        let chosen = best ?? ordered[0]
        return (chosen.id, direction(for: chosen.frame))
    }

    /// Row clustering of every pane currently in `root`, for tests to
    /// verify a final layout's shape directly (e.g. "6 panes form 2
    /// rows of 3") rather than only the step-by-step target/direction
    /// sequence that produced it. Internal (not `public`): this is a
    /// verification hook for `@testable import`, not part of the
    /// documented `mytty-ctl` placement contract.
    static func rowGroups(
        in root: SplitNode,
        containerAspectRatio: Double = defaultContainerAspectRatio
    ) -> [[TerminalSurfaceID]] {
        let aspect = normalizedAspectRatio(containerAspectRatio)
        let frames = root.balancedPaneFrames(containerAspectRatio: aspect)
        return rowGroups(from: frames).map { $0.map(\.id) }
    }

    private static func normalizedAspectRatio(_ aspectRatio: Double) -> Double {
        aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : defaultContainerAspectRatio
    }

    private static func direction(for frame: PaneFrame) -> SplitDirection {
        frame.width >= frame.height ? .right : .down
    }

    /// Groups frames into rows by vertical-overlap clustering: two
    /// frames belong to the same row when their vertical overlap
    /// exceeds 50% of the shorter frame's height, and the relation's
    /// transitive closure forms each row -- a pane spanning multiple
    /// stacked panes (e.g. a full-height pane beside a 2-high column)
    /// merges those into one cluster, which is fine: this is only ever
    /// used as a tie-break/verification score, not a rendering layout.
    private static func rowGroups(from frames: [PaneLayout]) -> [[PaneLayout]] {
        var clusters: [[PaneLayout]] = frames.map { [$0] }
        var merged = true
        while merged {
            merged = false
            mergeSearch: for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let overlaps = clusters[i].contains { lhs in
                        clusters[j].contains { rhs in
                            verticalOverlapRatio(lhs.frame, rhs.frame) > 0.5
                        }
                    }
                    guard overlaps else { continue }
                    clusters[i] += clusters[j]
                    clusters.remove(at: j)
                    merged = true
                    break mergeSearch
                }
            }
        }
        return clusters
    }

    private static func verticalOverlapRatio(
        _ lhs: PaneFrame,
        _ rhs: PaneFrame
    ) -> Double {
        let overlap = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
        let shorterHeight = min(lhs.height, rhs.height)
        guard shorterHeight > 0 else { return 0 }
        return overlap / shorterHeight
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
    /// A name derived from the agent conversation running in this tab
    /// (`AutoTabNaming` in `MyTTYApp`), refreshed after each completed
    /// turn. Shown only when `pinnedTitle` is nil, so a manual rename is
    /// never overwritten by a later automatic one.
    public var autoTitle: String?
    /// When the tab was first opened. Survives session restoration and
    /// moving the tab between windows.
    public let createdAt: Date

    public var surfaceIDs: [TerminalSurfaceID] {
        root.surfaceIDs
    }

    public var paneIDs: [TerminalSurfaceID] {
        root.paneIDs
    }

    public init(
        id: TabID = TabID(),
        initialSurface: TerminalSurfaceState,
        pinnedTitle: String? = nil,
        autoTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.root = .surface(initialSurface)
        self.focusedSurfaceID = initialSurface.id
        self.pinnedTitle = pinnedTitle
        self.autoTitle = autoTitle
        self.createdAt = createdAt
    }

    public init(
        id: TabID = TabID(),
        initialBrowser: BrowserPaneState,
        pinnedTitle: String? = nil,
        autoTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.root = .browser(initialBrowser)
        self.focusedSurfaceID = initialBrowser.id
        self.pinnedTitle = pinnedTitle
        self.autoTitle = autoTitle
        self.createdAt = createdAt
    }

    public init(
        id: TabID = TabID(),
        initialRemote: RemotePaneState,
        pinnedTitle: String? = nil,
        autoTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.root = .remote(initialRemote)
        self.focusedSurfaceID = initialRemote.id
        self.pinnedTitle = pinnedTitle
        self.autoTitle = autoTitle
        self.createdAt = createdAt
    }

    public init(
        id: TabID = TabID(),
        root: SplitNode,
        focusedSurfaceID: TerminalSurfaceID,
        pinnedTitle: String? = nil,
        autoTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.root = root
        self.focusedSurfaceID = focusedSurfaceID
        self.pinnedTitle = pinnedTitle
        self.autoTitle = autoTitle
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case root
        case focusedSurfaceID
        case pinnedTitle
        case autoTitle
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TabID.self, forKey: .id)
        root = try container.decode(SplitNode.self, forKey: .root)
        focusedSurfaceID = try container.decode(
            TerminalSurfaceID.self,
            forKey: .focusedSurfaceID
        )
        pinnedTitle = try container.decodeIfPresent(
            String.self,
            forKey: .pinnedTitle
        )
        // Snapshots written before auto-naming have no autoTitle key.
        autoTitle = try container.decodeIfPresent(
            String.self,
            forKey: .autoTitle
        )
        // Snapshots written before uptime tracking have no createdAt;
        // counting from restore is the closest available origin.
        createdAt = try container.decodeIfPresent(
            Date.self,
            forKey: .createdAt
        ) ?? Date()
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
        direction: SplitDirection,
        focus: Bool = true
    ) throws {
        try split(
            pane: targetID,
            adding: .surface(newSurface),
            id: newSurface.id,
            direction: direction,
            focus: focus
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

    public mutating func split(
        remote: RemotePaneState,
        direction: SplitDirection
    ) throws {
        try split(
            pane: focusedSurfaceID,
            adding: .remote(remote),
            id: remote.id,
            direction: direction
        )
    }

    /// Splits at the root of the pane tree instead of inside the focused
    /// pane: the new surface takes one half of the whole tab, and the
    /// existing layout is squeezed into the other half.
    public mutating func splitOuter(
        adding newSurface: TerminalSurfaceState,
        direction: SplitDirection
    ) throws {
        guard !root.contains(newSurface.id) else {
            throw TabSessionError.duplicateSurface(newSurface.id)
        }
        root = Self.wrapped(
            root,
            adding: .surface(newSurface),
            direction: direction
        )
        focusedSurfaceID = newSurface.id
    }

    private mutating func split(
        pane targetID: TerminalSurfaceID,
        adding newNode: SplitNode,
        id newID: TerminalSurfaceID,
        direction: SplitDirection,
        focus: Bool = true
    ) throws {
        guard root.contains(targetID) else {
            throw TabSessionError.surfaceNotFound(targetID)
        }
        guard !root.contains(newID) else {
            throw TabSessionError.duplicateSurface(newID)
        }

        let replacement = root.replacing(pane: targetID) { targetNode in
            Self.wrapped(targetNode, adding: newNode, direction: direction)
        }

        guard let replacement else {
            throw TabSessionError.surfaceNotFound(targetID)
        }
        root = replacement
        if focus {
            focusedSurfaceID = newID
        }
    }

    /// `fileprivate` rather than `private` so `BalancedPaneInsertion`'s
    /// tie-break simulation (same file) can build the same wrapped node
    /// a real split would, without duplicating this switch.
    fileprivate static func wrapped(
        _ targetNode: SplitNode,
        adding newNode: SplitNode,
        direction: SplitDirection
    ) -> SplitNode {
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

    /// Removes the pane's leaf node and returns it so it can be
    /// reinserted into another tab. Same constraints and focus fixup
    /// as `close(pane:)`.
    public mutating func detach(
        pane id: TerminalSurfaceID
    ) throws -> SplitNode {
        guard let leaf = root.leaf(for: id) else {
            throw TabSessionError.surfaceNotFound(id)
        }
        try close(pane: id)
        return leaf
    }

    /// Inserts an existing pane subtree at the right-hand outer edge of
    /// the layout and focuses its first pane.
    public mutating func attach(pane node: SplitNode) throws {
        for id in node.paneIDs where root.contains(id) {
            throw TabSessionError.duplicateSurface(id)
        }
        root = Self.wrapped(root, adding: node, direction: .right)
        if let first = node.paneIDs.first {
            focusedSurfaceID = first
        }
    }

    /// Inserts an existing pane subtree at the balanced-placement
    /// position `BalancedPaneInsertion` computes, instead of always the
    /// outer right edge `attach(pane:)` uses — used to park a finished
    /// worker into a done tab without producing a 1×N strip. Falls back
    /// to `attach(pane:)` if the algorithm can't find a target (an
    /// empty tab, which shouldn't occur for a real `TabSession`).
    public mutating func attachBalanced(
        pane node: SplitNode,
        containerAspectRatio: Double = BalancedPaneInsertion
            .defaultContainerAspectRatio
    ) throws {
        for id in node.paneIDs where root.contains(id) {
            throw TabSessionError.duplicateSurface(id)
        }
        guard let target = BalancedPaneInsertion.target(
            in: root,
            containerAspectRatio: containerAspectRatio
        ), let replacement = root.replacing(pane: target.paneID, with: {
            targetNode in
            Self.wrapped(targetNode, adding: node, direction: target.direction)
        }) else {
            root = Self.wrapped(root, adding: node, direction: .right)
            if let first = node.paneIDs.first {
                focusedSurfaceID = first
            }
            return
        }
        root = replacement
        if let first = node.paneIDs.first {
            focusedSurfaceID = first
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

    public mutating func updateRemoteTitle(
        _ title: String,
        for id: TerminalSurfaceID
    ) throws {
        guard let replacement = root.replacing(pane: id, with: { node in
            guard case var .remote(remote) = node else { return node }
            remote.title = title
            return .remote(remote)
        }), root.remoteState(with: id) != nil else {
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
