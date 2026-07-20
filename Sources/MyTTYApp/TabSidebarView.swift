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
        guard let sourceIndex = orderedIDs.firstIndex(of: sourceID) else {
            return nil
        }
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
        return orderedIDs[destination]
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
    let onFocusAttentionItem: (AttentionItem) -> Void
    let onAcknowledgeAttentionItem: (AttentionItem) -> Void
    let onAcknowledgeAllAttentionItems: () -> Void
    let onAttentionPopoverDismissed: () -> Void
    let onSplit: (SplitDirection) -> Void
    let onClosePane: () -> Void
    let onStopRecording: (TabID) -> Void

    private static let tabAreaSpace = "tabAreaSpace"

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
            dragHandle

            Button {
                onSelect(row.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
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
                        TabStatusIndicators(
                            row: row,
                            localizer: localizer
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Fill the row's full height so the padding above and
                // below the label still hits the button.
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .onDrop(
            of: TabDragPasteboard.acceptedTypes,
            delegate: rowDropDelegate(for: row)
        )
    }

    private func horizontalTab(_ row: TabSidebarRow) -> some View {
        let selected = model.selectedTabID == row.id

        return HStack(spacing: 6) {
            dragHandle

            Button {
                onSelect(row.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .foregroundStyle(
                            selected ? Color.accentColor : .secondary
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        TabStatusIndicators(
                            row: row,
                            localizer: localizer
                        )
                    }
                    if row.attentionCount > 0 {
                        Text("\(row.attentionCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                // Fill the row's full height so the padding above the
                // title and below the icon still hits the button.
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .onDrop(
            of: TabDragPasteboard.acceptedTypes,
            delegate: rowDropDelegate(for: row)
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

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(width: 14, height: 24)
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
                    onDetachDrag(row.id)
                    return
                }
                dragPresentation = TabDragPresentation(
                    tabID: row.id,
                    translation: value.translation
                )
            }
            .onEnded { value in
                dragPresentation = nil
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

private struct TabStatusIndicators: View {
    let row: TabSidebarRow
    let localizer: MyTTYLocalizer

    var body: some View {
        HStack(spacing: 6) {
            if let paneCount = row.visiblePaneCount {
                HStack(spacing: 2) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 9))
                    Text("\(paneCount)")
                        .font(.caption2.monospacedDigit())
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localizer.paneCount(paneCount))
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
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.isTabDropTargeted = false
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
    }

    func dropExited(info: DropInfo) {
        model.isTabDropTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.isTabDropTargeted = false
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
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 14, height: 24)
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
