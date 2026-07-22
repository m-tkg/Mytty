import MyTTYCore
import SwiftUI
import UniformTypeIdentifiers

enum TabDragActivationArea: Equatable {
    case entireTab
}

struct TabDragInteractionPolicy: Equatable {
    /// 8pt before a press counts as a reorder drag: once the drag starts,
    /// its preview moves the row out from under the cursor and cancels the
    /// row's buttons, so a lower threshold makes ordinary slightly-sloppy
    /// clicks (especially on the close button) feel unresponsive.
    static let reorder = Self(
        activationArea: .entireTab,
        minimumDistance: 8
    )

    let activationArea: TabDragActivationArea
    let minimumDistance: CGFloat
}

struct TabDragPresentation: Equatable {
    private static let draggedSourceOpacity = 0.35
    static let movingPreviewOpacity = 0.72

    let tabID: TabID
    let translation: CGSize

    var previewOpacity: Double {
        Self.movingPreviewOpacity
    }

    func sourceOpacity(for candidateID: TabID) -> Double {
        candidateID == tabID ? Self.draggedSourceOpacity : 1
    }
}

enum TabReorderPlan {
    static func targetID(
        for sourceID: TabID,
        translation: CGSize,
        placement: MyTTYTabPlacement,
        orderedIDs: [TabID]
    ) -> TabID? {
        guard let sourceIndex = orderedIDs.firstIndex(of: sourceID),
              let destination = destinationIndex(
                sourceIndex: sourceIndex,
                translation: translation,
                placement: placement,
                orderedIDs: orderedIDs
              )
        else { return nil }
        return orderedIDs[destination]
    }

    /// The insertion point (`model.rows` index) a live drag currently
    /// implies: `0` is before the first row, `orderedIDs.count` is after
    /// the last. Nil while the drag hasn't moved far enough to change
    /// anything, matching `targetID`.
    static func insertionIndex(
        for sourceID: TabID,
        translation: CGSize,
        placement: MyTTYTabPlacement,
        orderedIDs: [TabID]
    ) -> Int? {
        guard let sourceIndex = orderedIDs.firstIndex(of: sourceID),
              let destination = destinationIndex(
                sourceIndex: sourceIndex,
                translation: translation,
                placement: placement,
                orderedIDs: orderedIDs
              )
        else { return nil }
        return destination > sourceIndex ? destination + 1 : destination
    }

    private static func destinationIndex(
        sourceIndex: Int,
        translation: CGSize,
        placement: MyTTYTabPlacement,
        orderedIDs: [TabID]
    ) -> Int? {
        let distance: CGFloat
        let itemStride: CGFloat
        switch placement {
        case .left, .right:
            distance = translation.height
            itemStride = 53
        case .top, .bottom:
            distance = translation.width
            itemStride = 193
        }
        let offset = Int((distance / itemStride).rounded())
        guard offset != 0 else { return nil }
        let destination = min(
            max(sourceIndex + offset, orderedIDs.startIndex),
            orderedIDs.index(before: orderedIDs.endIndex)
        )
        guard destination != sourceIndex else { return nil }
        return destination
    }
}

struct TabSidebarRow: Identifiable, Equatable {
    let id: TabID
    let title: String
    let paneCount: Int
    let attentionCount: Int
    let hasRunningAgent: Bool
    var isRecording = false
    var hasCollapsedPanes = false
    var resourceURL: URL? = nil
    /// When the tab was opened, driving the elapsed-time indicator. Nil
    /// hides the indicator (the "show elapsed time" setting is off).
    var uptimeOrigin: Date? = nil
    /// Position among the tabs, 1-based, top to bottom. `0` means "no
    /// number" and hides the digit under the drag handle.
    var number = 0

    var visiblePaneCount: Int? {
        paneCount > 0 ? paneCount : nil
    }

    var canEqualizePanes: Bool {
        paneCount > 1
    }

    var hasStatusIndicators: Bool {
        visiblePaneCount != nil || hasRunningAgent || isRecording
    }
}

@MainActor
final class TabSidebarModel: ObservableObject {
    @Published var rows: [TabSidebarRow] = []
    @Published var selectedTabID: TabID?
    @Published var actionableAttentionCount = 0
    @Published var isRemoteAccessConnected = false
    @Published var isAttentionPresented = false
    @Published var isTabDropTargeted = false
    /// The insertion point a drag (reorder or cross-window drop) currently
    /// implies, as an index into `rows`: `0` is before the first row,
    /// `rows.count` is after the last. Nil while nothing is being dragged
    /// over the sidebar, which hides the drop-indicator line.
    @Published var dropInsertionIndex: Int?
    var promotedDragTabID: TabID?

    func canMoveUp(_ id: TabID) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return index > rows.startIndex
    }

    func canMoveDown(_ id: TabID) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return index < rows.index(before: rows.endIndex)
    }
}

struct TabSidebarView: View {
    @ObservedObject var model: TabSidebarModel
    @ObservedObject var attentionCenter: AttentionCenter
    @State private var dragPresentation: TabDragPresentation?
    @State private var tabAreaSize: CGSize = .zero
    let placement: MyTTYTabPlacement
    let localizer: MyTTYLocalizer
    let attentionUnreadOnly: Bool
    let onSelect: (TabID) -> Void
    let onNewTab: () -> Void
    let onClose: (TabID) -> Void
    let onRename: (TabID) -> Void
    let onCopyPath: (TabID) -> Void
    let onRevealInFinder: (TabID) -> Void
    let onMoveUp: (TabID) -> Void
    let onMoveDown: (TabID) -> Void
    let onReorder: (TabID, TabID) -> Void
    let onDetachDrag: (TabID) -> Void
    let onDropTab: (Int) -> Void
    let isTabDragActive: () -> Bool
    let onEqualizePanes: (TabID) -> Void
    let onPaneProcesses: (TabID) -> [PaneListItem]
    let onFocusAttentionItem: (AttentionItem) -> Void
    let onAcknowledgeAttentionItem: (AttentionItem) -> Void
    let onAcknowledgeAllAttentionItems: () -> Void
    let onAttentionPopoverDismissed: () -> Void
    let onSplit: (SplitDirection) -> Void
    let onClosePane: () -> Void
    let onStopRecording: (TabID) -> Void

    private static let tabAreaSpace = "tabAreaSpace"

    /// Where the pane-process popover opens relative to its anchor. The
    /// sidebar is at most 280pt wide, narrower than the popover, so a
    /// vertical sidebar opens it sideways over the terminal instead of
    /// letting the window edge clip it.
    private var processPopoverArrowEdge: Edge {
        switch placement {
        case .left: .trailing
        case .right: .leading
        case .top: .bottom
        case .bottom: .top
        }
    }

    var body: some View {
        Group {
            switch placement {
            case .left, .right:
                verticalTabs
            case .top, .bottom:
                horizontalTabs
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .coordinateSpace(name: Self.tabAreaSpace)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            tabAreaSize = size
        }
        .onDrop(
            of: TabDragPasteboard.acceptedTypes,
            delegate: TabAreaDropDelegate(
                model: model,
                isTabDragActive: isTabDragActive,
                onDrop: onDropTab
            )
        )
        .overlay {
            if model.isTabDropTargeted {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay {
                        Rectangle()
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private var verticalTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(localizer[.tabs])
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                controls
            }
            .padding(.horizontal, 12)
            .frame(height: 42)

            Divider()

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.rows) { row in
                        tabRow(row)
                    }
                }
                .padding(6)
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
    }

    private var horizontalTabs: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 3) {
                    ForEach(model.rows) { row in
                        horizontalTab(row)
                    }
                }
                .padding(.horizontal, 6)
            }

            Divider()
            controls
                .padding(.horizontal, 8)
        }
        .frame(height: 44)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .frame(width: 20, height: 20)
                .foregroundStyle(
                    model.isRemoteAccessConnected
                        ? Color.green
                        : Color.secondary.opacity(0.5)
                )
                .help(
                    model.isRemoteAccessConnected
                        ? localizer[.iosRemoteConnected]
                        : localizer[.iosRemoteNotConnected]
                )
                .accessibilityLabel(
                    model.isRemoteAccessConnected
                        ? localizer[.iosRemoteConnected]
                        : localizer[.iosRemoteNotConnected]
                )

            Button(action: { model.isAttentionPresented.toggle() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .frame(width: 20, height: 20)
                    if model.actionableAttentionCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(.background, lineWidth: 1))
                    }
                }
            }
            .buttonStyle(.plain)
            .help(localizer[.toggleAttention])
            .accessibilityLabel(
                model.actionableAttentionCount > 0
                    ? localizer.attentionCount(
                        model.actionableAttentionCount
                    )
                    : localizer[.attention]
            )
            .popover(
                isPresented: Binding(
                    get: { model.isAttentionPresented },
                    set: { presented in
                        model.isAttentionPresented = presented
                        if !presented { onAttentionPopoverDismissed() }
                    }
                ),
                arrowEdge: .bottom
            ) {
                AttentionDrawerView(
                    center: attentionCenter,
                    localizer: localizer,
                    showsUnreadOnly: attentionUnreadOnly,
                    onClose: {
                        model.isAttentionPresented = false
                        onAttentionPopoverDismissed()
                    },
                    onFocus: onFocusAttentionItem,
                    onAcknowledge: onAcknowledgeAttentionItem,
                    onAcknowledgeAll: onAcknowledgeAllAttentionItems
                )
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(localizer[.newTab])
            .accessibilityLabel(localizer[.newTab])

            Menu {
                Button(localizer[.splitLeft]) { onSplit(.left) }
                Button(localizer[.splitRight]) { onSplit(.right) }
                Button(localizer[.splitUp]) { onSplit(.up) }
                Button(localizer[.splitDown]) { onSplit(.down) }
                Divider()
                Button(localizer[.closePane], action: onClosePane)
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(localizer[.paneActions])
            .accessibilityLabel(localizer[.paneActions])
        }
    }

    private func tabRow(_ row: TabSidebarRow) -> some View {
        let selected = model.selectedTabID == row.id

        return HStack(spacing: 8) {
            dragHandle(number: row.number)

            VStack(alignment: .leading, spacing: 2) {
                // The select button covers only the title row: nesting
                // the pane-process button inside it makes hit-testing
                // flaky and merges both into one accessibility element,
                // so the indicators row below stays a sibling. Clicks on
                // the rest of the row still select via the row-level tap
                // gesture.
                Button {
                    onSelect(row.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .foregroundStyle(
                                selected ? Color.accentColor : .secondary
                            )
                            .frame(width: 16, height: 16)
                        Text(row.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if row.attentionCount > 0 {
                            Text("\(row.attentionCount)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 16)
                                .foregroundStyle(.white)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                TabStatusIndicators(
                    row: row,
                    localizer: localizer,
                    paneProcessProvider: onPaneProcesses,
                    processPopoverArrowEdge: processPopoverArrowEdge
                )
                .padding(.leading, 24)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
            )

            if row.isRecording {
                Button {
                    onStopRecording(row.id)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .frame(width: 18)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(localizer[.stopRecording])
                .accessibilityLabel(localizer[.stopRecording])
            }

            Button {
                onClose(row.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizer[.closeTab])
            .accessibilityLabel(localizer.closeTitle(row.title))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 50)
        .background(
            selected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        // Clicks anywhere in the row that no inner button consumes still
        // select the tab, keeping the full-row target the old whole-row
        // button provided.
        .onTapGesture { onSelect(row.id) }
        .simultaneousGesture(reorderGesture(for: row))
        .modifier(tabInteractions(for: row))
        .modifier(
            TabDragPresentationModifier(
                row: row,
                placement: placement,
                selected: selected,
                localizer: localizer,
                presentation: dragPresentation
            )
        )
        .modifier(dropIndicator(for: row))
        .onDrop(
            of: TabDragPasteboard.acceptedTypes,
            delegate: rowDropDelegate(for: row)
        )
    }

    private func horizontalTab(_ row: TabSidebarRow) -> some View {
        let selected = model.selectedTabID == row.id

        return HStack(spacing: 6) {
            dragHandle(number: row.number)

            VStack(alignment: .leading, spacing: 1) {
                // Same sibling structure as the vertical row: the select
                // button covers the title row only, the interactive
                // indicators live outside it.
                Button {
                    onSelect(row.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .foregroundStyle(
                                selected ? Color.accentColor : .secondary
                            )
                        Text(row.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if row.attentionCount > 0 {
                            Text("\(row.attentionCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                TabStatusIndicators(
                    row: row,
                    localizer: localizer,
                    paneProcessProvider: onPaneProcesses,
                    processPopoverArrowEdge: processPopoverArrowEdge
                )
                .padding(.leading, 20)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
            )

            if row.isRecording {
                Button {
                    onStopRecording(row.id)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(width: 16)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(localizer[.stopRecording])
                .accessibilityLabel(localizer[.stopRecording])
            }

            Button {
                onClose(row.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 16)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizer[.closeTab])
            .accessibilityLabel(localizer.closeTitle(row.title))
        }
        .padding(.horizontal, 9)
        .frame(width: 190, height: 40)
        .background(
            selected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        // Clicks anywhere in the row that no inner button consumes still
        // select the tab, keeping the full-row target the old whole-row
        // button provided.
        .onTapGesture { onSelect(row.id) }
        .simultaneousGesture(reorderGesture(for: row))
        .modifier(tabInteractions(for: row))
        .modifier(
            TabDragPresentationModifier(
                row: row,
                placement: placement,
                selected: selected,
                localizer: localizer,
                presentation: dragPresentation
            )
        )
        .modifier(dropIndicator(for: row))
        .onDrop(
            of: TabDragPasteboard.acceptedTypes,
            delegate: rowDropDelegate(for: row)
        )
    }

    private func dropIndicator(
        for row: TabSidebarRow
    ) -> TabDropIndicatorModifier {
        let index = model.rows.firstIndex(where: { $0.id == row.id }) ?? 0
        return TabDropIndicatorModifier(
            index: index,
            isLastRow: index == model.rows.count - 1,
            placement: placement,
            dropInsertionIndex: model.dropInsertionIndex,
            rowCount: model.rows.count
        )
    }

    private func rowDropDelegate(for row: TabSidebarRow) -> TabRowDropDelegate {
        TabRowDropDelegate(
            rowIndex: model.rows.firstIndex(where: { $0.id == row.id }) ?? 0,
            rowSize: placement.isVertical
                ? CGSize(width: 0, height: 50)
                : CGSize(width: 190, height: 40),
            placement: placement,
            model: model,
            isTabDragActive: isTabDragActive,
            onDrop: onDropTab
        )
    }

    private func tabInteractions(
        for row: TabSidebarRow
    ) -> TabInteractionModifier {
        TabInteractionModifier(
            row: row,
            localizer: localizer,
            canMoveUp: model.canMoveUp(row.id),
            canMoveDown: model.canMoveDown(row.id),
            canEqualizePanes: row.canEqualizePanes,
            onRename: onRename,
            onCopyPath: onCopyPath,
            onRevealInFinder: onRevealInFinder,
            onClose: onClose,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onEqualizePanes: onEqualizePanes
        )
    }

    private func dragHandle(number: Int) -> some View {
        TabDragHandleGlyph(number: number)
            .contentShape(Rectangle())
            .help(localizer[.reorderTab])
            .accessibilityLabel(localizer[.reorderTab])
    }

    private func reorderGesture(for row: TabSidebarRow) -> some Gesture {
        DragGesture(
            minimumDistance: TabDragInteractionPolicy.reorder.minimumDistance,
            coordinateSpace: .named(Self.tabAreaSpace)
        )
            .onChanged { value in
                guard model.promotedDragTabID == nil else { return }
                if TabDragPromotionPlan.shouldPromote(
                    location: value.location,
                    tabAreaSize: tabAreaSize
                ) {
                    model.promotedDragTabID = row.id
                    dragPresentation = nil
                    model.dropInsertionIndex = nil
                    onDetachDrag(row.id)
                    return
                }
                dragPresentation = TabDragPresentation(
                    tabID: row.id,
                    translation: value.translation
                )
                model.dropInsertionIndex = TabReorderPlan.insertionIndex(
                    for: row.id,
                    translation: value.translation,
                    placement: placement,
                    orderedIDs: model.rows.map(\.id)
                )
            }
            .onEnded { value in
                dragPresentation = nil
                model.dropInsertionIndex = nil
                guard model.promotedDragTabID == nil else { return }
                guard let targetID = TabReorderPlan.targetID(
                    for: row.id,
                    translation: value.translation,
                    placement: placement,
                    orderedIDs: model.rows.map(\.id)
                ) else {
                    // The press moved enough to start the drag but never
                    // reached another slot — a sloppy click, not a
                    // reorder. The drag preview already cancelled the row
                    // button's own tap, so deliver the intended selection.
                    onSelect(row.id)
                    return
                }
                onReorder(row.id, targetID)
            }
    }

}

/// The 3-line drag handle glyph with the tab's position stacked below it,
/// in the same `.tertiary` color. Shared by the sidebar row (`dragHandle`)
/// and its drag preview (`TabDragPreview`) so the two stay identical.
private struct TabDragHandleGlyph: View {
    let number: Int

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            if number > 0 {
                Text("\(number)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 14, height: 24)
    }
}

private struct TabStatusIndicators: View {
    let row: TabSidebarRow
    let localizer: MyTTYLocalizer
    /// Supplies the tab's panes and their foreground commands when the
    /// pane-count indicator is clicked. Nil renders the indicator as a
    /// plain, non-interactive glyph (the drag preview).
    var paneProcessProvider: ((TabID) -> [PaneListItem])? = nil
    var processPopoverArrowEdge: Edge = .bottom
    /// Presentation trigger and content in one value: `popover(item:)`
    /// snapshots the items in the same transaction that presents, so the
    /// content can never render a stale (empty) list the way a separate
    /// `isPresented` Bool alongside an items array can.
    @State private var processPopover: TabPaneProcessPopover?

    var body: some View {
        HStack(spacing: 6) {
            if let paneCount = row.visiblePaneCount {
                paneCountIndicator(paneCount)
            }
            if let uptimeOrigin = row.uptimeOrigin {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let uptime = TabUptimeFormatter.string(
                        from: context.date.timeIntervalSince(uptimeOrigin)
                    )
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(uptime)
                            .font(.caption2.monospacedDigit())
                    }
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(localizer[.tabUptime]) \(uptime)"
                    )
                }
            }
            if row.hasCollapsedPanes {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9))
                    .help(localizer[.paneZoomed])
                    .accessibilityLabel(localizer[.paneZoomed])
            }
            if row.hasRunningAgent {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel(
                        "\(localizer[.agents]) \(localizer[.running])"
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 14)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func paneCountIndicator(_ paneCount: Int) -> some View {
        if let paneProcessProvider {
            Button {
                processPopover = TabPaneProcessPopover(
                    items: paneProcessProvider(row.id)
                )
            } label: {
                paneCountLabel(paneCount)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizer[.paneProcesses])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localizer.paneCount(paneCount))
            .accessibilityHint(localizer[.paneProcesses])
            .popover(
                item: $processPopover,
                arrowEdge: processPopoverArrowEdge
            ) { popover in
                TabPaneProcessListView(
                    items: popover.items,
                    localizer: localizer
                )
            }
        } else {
            paneCountLabel(paneCount)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localizer.paneCount(paneCount))
        }
    }

    private func paneCountLabel(_ paneCount: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 9))
            Text("\(paneCount)")
                .font(.caption2.monospacedDigit())
        }
        .fixedSize()
    }
}

struct TabPaneProcessPopover: Identifiable {
    let id = UUID()
    let items: [PaneListItem]
}

/// The popover the sidebar's pane-count indicator opens: one row per pane
/// in the tab, showing the foreground command and its location.
struct TabPaneProcessListView: View {
    let items: [PaneListItem]
    let localizer: MyTTYLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer[.paneProcesses])
                .font(.headline)
            if items.isEmpty {
                Text(localizer[.noPanes])
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(
                            systemName: item.kind == .terminal
                                ? "terminal"
                                : "globe"
                        )
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(item.command)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                if item.isActive {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 5))
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text(item.location)
                                .font(
                                    .system(size: 11, design: .monospaced)
                                )
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(item.location)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: 340, alignment: .leading)
    }
}

private struct TabDragPresentationModifier: ViewModifier {
    let row: TabSidebarRow
    let placement: MyTTYTabPlacement
    let selected: Bool
    let localizer: MyTTYLocalizer
    let presentation: TabDragPresentation?

    func body(content: Content) -> some View {
        let isDragged = presentation?.tabID == row.id

        content
            .opacity(presentation?.sourceOpacity(for: row.id) ?? 1)
            .overlay {
                if let presentation, isDragged {
                    TabDragPreview(
                        row: row,
                        placement: placement,
                        selected: selected,
                        localizer: localizer
                    )
                    .opacity(presentation.previewOpacity)
                    .offset(presentation.translation)
                    .allowsHitTesting(false)
                }
            }
            .zIndex(isDragged ? 1 : 0)
    }
}

/// Draws the blue insertion line a drag (either an in-window reorder or a
/// cross-window drop) implies, without disturbing row layout: the line is
/// an overlay, never an inserted spacer, so rows never shift to make room
/// for it.
private struct TabDropIndicatorModifier: ViewModifier {
    /// This row's position among `model.rows`.
    let index: Int
    let isLastRow: Bool
    let placement: MyTTYTabPlacement
    let dropInsertionIndex: Int?
    let rowCount: Int

    private static let thickness: CGFloat = 3
    private static let cornerRadius: CGFloat = 1.5
    /// Matches the `LazyVStack`/`LazyHStack` `spacing` the sidebar lays
    /// tab rows out with, so the line renders centered in the gap between
    /// two rows instead of overlapping either one.
    private static let rowSpacing: CGFloat = 3
    private static let edgeShift = rowSpacing / 2 + thickness / 2

    func body(content: Content) -> some View {
        content
            .overlay(alignment: leadingEdge) {
                if dropInsertionIndex == index {
                    line.offset(leadingOffset)
                }
            }
            .overlay(alignment: trailingEdge) {
                if isLastRow, dropInsertionIndex == rowCount {
                    line.offset(trailingOffset)
                }
            }
    }

    private var line: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(Color.accentColor)
            .frame(
                width: placement.isVertical ? nil : Self.thickness,
                height: placement.isVertical ? Self.thickness : nil
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var leadingEdge: Alignment {
        placement.isVertical ? .top : .leading
    }

    private var trailingEdge: Alignment {
        placement.isVertical ? .bottom : .trailing
    }

    private var leadingOffset: CGSize {
        placement.isVertical
            ? CGSize(width: 0, height: -Self.edgeShift)
            : CGSize(width: -Self.edgeShift, height: 0)
    }

    private var trailingOffset: CGSize {
        placement.isVertical
            ? CGSize(width: 0, height: Self.edgeShift)
            : CGSize(width: Self.edgeShift, height: 0)
    }
}

struct TabRowDropDelegate: DropDelegate {
    let rowIndex: Int
    let rowSize: CGSize
    let placement: MyTTYTabPlacement
    let model: TabSidebarModel
    let isTabDragActive: () -> Bool
    let onDrop: (Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isTabDragActive()
    }

    func dropEntered(info: DropInfo) {
        model.isTabDropTargeted = true
    }

    func dropExited(info: DropInfo) {
        model.isTabDropTargeted = false
        model.dropInsertionIndex = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        model.dropInsertionIndex = TabDropInsertionPlan.insertionIndex(
            rowIndex: rowIndex,
            location: info.location,
            rowSize: rowSize,
            placement: placement
        )
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.isTabDropTargeted = false
        model.dropInsertionIndex = nil
        onDrop(
            TabDropInsertionPlan.insertionIndex(
                rowIndex: rowIndex,
                location: info.location,
                rowSize: rowSize,
                placement: placement
            )
        )
        return true
    }
}

struct TabAreaDropDelegate: DropDelegate {
    let model: TabSidebarModel
    let isTabDragActive: () -> Bool
    let onDrop: (Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isTabDragActive()
    }

    func dropEntered(info: DropInfo) {
        model.isTabDropTargeted = true
        model.dropInsertionIndex = model.rows.count
    }

    func dropExited(info: DropInfo) {
        model.isTabDropTargeted = false
        model.dropInsertionIndex = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        model.dropInsertionIndex = model.rows.count
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.isTabDropTargeted = false
        model.dropInsertionIndex = nil
        onDrop(model.rows.count)
        return true
    }
}

struct TabDragPreview: View {
    let row: TabSidebarRow
    let placement: MyTTYTabPlacement
    let selected: Bool
    let localizer: MyTTYLocalizer

    var body: some View {
        HStack(spacing: placement.isVertical ? 8 : 6) {
            TabDragHandleGlyph(number: row.number)
            Image(systemName: "terminal")
                .foregroundStyle(
                    selected ? Color.accentColor : .secondary
                )
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(
                        .system(
                            size: placement.isVertical ? 13 : 12,
                            weight: .medium
                        )
                    )
                    .lineLimit(1)
                TabStatusIndicators(row: row, localizer: localizer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.attentionCount > 0 {
                Text("\(row.attentionCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Color.accentColor, in: Capsule())
            }
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(
                    width: placement.isVertical ? 18 : 16,
                    height: placement.isVertical ? 18 : 16
                )
        }
        .padding(.leading, placement.isVertical ? 8 : 9)
        .padding(.trailing, placement.isVertical ? 6 : 9)
        .frame(
            width: placement.isVertical ? nil : 190,
            height: placement.isVertical ? 50 : 40
        )
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .accessibilityHidden(true)
    }
}

private struct TabInteractionModifier: ViewModifier {
    let row: TabSidebarRow
    let localizer: MyTTYLocalizer
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canEqualizePanes: Bool
    let onRename: (TabID) -> Void
    let onCopyPath: (TabID) -> Void
    let onRevealInFinder: (TabID) -> Void
    let onClose: (TabID) -> Void
    let onMoveUp: (TabID) -> Void
    let onMoveDown: (TabID) -> Void
    let onEqualizePanes: (TabID) -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(localizer[.renameTab]) { onRename(row.id) }
                Divider()
                Button(localizer[.copyPath]) { onCopyPath(row.id) }
                    .disabled(row.resourceURL == nil)
                Button(localizer[.revealInFinder]) {
                    onRevealInFinder(row.id)
                }
                .disabled(row.resourceURL?.isFileURL != true)
                Divider()
                Button(localizer[.closeTab]) { onClose(row.id) }
                Divider()
                Button(localizer[.equalizePanes]) {
                    onEqualizePanes(row.id)
                }
                .disabled(!canEqualizePanes)
                Divider()
                Button(localizer[.moveUp]) { onMoveUp(row.id) }
                    .disabled(!canMoveUp)
                Button(localizer[.moveDown]) { onMoveDown(row.id) }
                    .disabled(!canMoveDown)
            }
    }
}
