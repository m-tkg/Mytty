import AppKit
import Combine
import MyTTYCore
import SwiftUI

enum PaneListWindowPlacement {
    static func centeredFrame(
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        NSRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    }
}

enum PaneListSelectionDirection: Equatable {
    case previous
    case next
}

enum PaneListKeyboardNavigation {
    static func direction(
        forKeyCode keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> PaneListSelectionDirection? {
        let commandModifiers = modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift,
        ])
        guard commandModifiers.isEmpty else { return nil }

        switch keyCode {
        case 126: return .previous
        case 125: return .next
        default: return nil
        }
    }
}

@MainActor
final class PaneListModel: ObservableObject {
    @Published var items: [PaneListItem] = []
    @Published var selectedID: PaneListItem.ID?
    @Published var localizer = MyTTYLocalizer(language: .systemDefault)

    var onFocus: (PaneListItem) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    func focus(_ item: PaneListItem) {
        onDismiss()
        onFocus(item)
    }

    func focusSelection() {
        guard let item = items.first(where: { $0.id == selectedID }) else {
            return
        }
        focus(item)
    }

    func select(_ item: PaneListItem) {
        selectedID = item.id
    }

    func activate(_ item: PaneListItem) {
        select(item)
        focus(item)
    }

    func moveSelection(_ direction: PaneListSelectionDirection) {
        guard !items.isEmpty else { return }
        let currentIndex = selectedID.flatMap { selectedID in
            items.firstIndex(where: { $0.id == selectedID })
        }
        let destination: Int
        switch direction {
        case .previous:
            destination = max((currentIndex ?? items.count) - 1, 0)
        case .next:
            destination = min((currentIndex ?? -1) + 1, items.count - 1)
        }
        selectedID = items[destination].id
    }
}

private struct PaneListView: View {
    @ObservedObject var model: PaneListModel

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(model.localizer[.noPanes])
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                paneTable
            }

            Divider()

            HStack {
                Spacer()
                Button(model.localizer[.cancel]) {
                    model.onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(model.localizer[.focusPane]) {
                    model.focusSelection()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedID == nil)
            }
            .padding(16)
        }
        .frame(minWidth: 460, minHeight: 320)
        .onExitCommand {
            model.onDismiss()
        }
    }

    private var paneTable: some View {
        ScrollViewReader { proxy in
            List(model.items, selection: $model.selectedID) { item in
                paneRow(item)
                    .tag(item.id)
                    .id(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.activate(item)
                    }
            }
            .listStyle(.inset)
            .onChange(of: model.selectedID) { _, selectedID in
                guard let selectedID else { return }
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
    }

    private func paneRow(_ item: PaneListItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(
                systemName: item.kind == .terminal ? "terminal" : "globe"
            )
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.command)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if item.isActive {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.tint)
                    }
                    Spacer(minLength: 8)
                    Label(item.tabTitle, systemImage: "rectangle.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .trailing)
                }

                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(item.location)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
                .help(item.location)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class PaneListWindowController: NSWindowController {
    private let model = PaneListModel()
    private var navigationEventMonitor: Any?

    init(onFocus: @escaping (PaneListItem) -> Void) {
        let hostingController = NSHostingController(
            rootView: PaneListView(model: model)
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.setContentSize(NSSize(width: 540, height: 400))
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 460, height: 320)
        panel.center()
        super.init(window: panel)

        model.onFocus = onFocus
        model.onDismiss = { [weak panel] in
            panel?.orderOut(nil)
        }
        startMonitoringNavigationKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        stopMonitoringNavigationKeys()
    }

    func present(
        items: [PaneListItem],
        selectedPaneID: TerminalSurfaceID?,
        visibleScreenFrame: NSRect?,
        localizer: MyTTYLocalizer
    ) {
        model.items = items
        model.selectedID = selectedPaneID.flatMap { paneID in
            items.first(where: { $0.paneID == paneID })?.id
        } ?? items.first?.id
        updateLocalization(localizer)
        if let visibleScreenFrame, let window {
            window.setFrame(
                PaneListWindowPlacement.centeredFrame(
                    windowSize: window.frame.size,
                    visibleFrame: visibleScreenFrame
                ),
                display: false
            )
        } else {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func updateLocalization(_ localizer: MyTTYLocalizer) {
        model.localizer = localizer
        window?.title = localizer.commandTitle(.showPaneList)
    }

    private func startMonitoringNavigationKeys() {
        guard navigationEventMonitor == nil else { return }
        navigationEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.window?.isVisible == true,
                  let direction = PaneListKeyboardNavigation.direction(
                    forKeyCode: event.keyCode,
                    modifierFlags: event.modifierFlags
                  )
            else { return event }
            self.model.moveSelection(direction)
            return nil
        }
    }

    private func stopMonitoringNavigationKeys() {
        guard let navigationEventMonitor else { return }
        NSEvent.removeMonitor(navigationEventMonitor)
        self.navigationEventMonitor = nil
    }
}
