import MyTTYRemoteKit
import SwiftUI
import UIKit

struct PaneDetailView: View {
    let pane: RemotePane
    @ObservedObject var client: RemoteClient

    @Environment(\.dismiss) private var dismiss
    @State private var activeModifiers: Set<ControlKey> = []
    @State private var keyboardShown = true
    /// The IME's in-progress composition (e.g. Japanese being converted),
    /// shown to the user because the invisible input view can't display it.
    @State private var composition = ""
    @State private var pinTracker = RemoteScrollPinTracker()
    /// The pane text pre-rendered into ~100-line attributed chunks. One
    /// giant `Text` stops drawing entirely past a few thousand lines (its
    /// backing layer exceeds what can be rasterized), so the buffer is
    /// split across many small `Text`s in a `LazyVStack`. Cached here so
    /// scrolling doesn't re-render the whole buffer on every body pass.
    @State private var renderedChunks: [AttributedString] = []
    /// Accumulates drag points not yet converted into whole wheel lines
    /// for remote (alternate-screen) scrolling.
    @State private var remoteScrollRemainder: CGFloat = 0
    private static let remoteScrollLineHeight: CGFloat = 17
    /// Frozen copy of the pane text shown in the selection sheet. Live
    /// screen updates rebuild the inline `Text` chunks and destroy any
    /// in-progress selection, so copying goes through a snapshot instead.
    /// Presented with `sheet(item:)` so the sheet is always built from
    /// the snapshot it was opened with, never a stale state value.
    @State private var selectionSnapshot: SelectionSnapshot?
    @State private var showsSchedules = false

    private struct SelectionSnapshot: Identifiable {
        let id = UUID()
        let text: String
    }

    private var isConnected: Bool { client.isConnected }

    var body: some View {
        VStack(spacing: 0) {
            if !isConnected {
                disconnectedBanner
            }

            // Follow new output only while the user is at the bottom:
            // `pinTracker` watches the content frame against the viewport
            // and scrolling up releases the pin, so screen updates never
            // yank the view down mid-read.
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(renderedChunks.indices, id: \.self) { index in
                                Text(renderedChunks[index])
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .id("content")
                        .background(
                            GeometryReader { content in
                                Color.clear.preference(
                                    key: PaneScrollContentFrameKey.self,
                                    value: content.frame(
                                        in: .named("paneScroll")
                                    )
                                )
                            }
                        )
                    }
                    // Open at the tail like a terminal; a `scrollTo` issued
                    // during the initial layout of a large buffer is
                    // unreliable and used to strand the view at the top.
                    .defaultScrollAnchor(.bottom)
                    .coordinateSpace(name: "paneScroll")
                    .background(Color(.systemBackground))
                    .contentShape(Rectangle())
                    // An alternate-screen TUI has no scrollback to mirror:
                    // scroll it remotely instead, letting the app (e.g. an
                    // agent's own history view) do the scrolling.
                    .scrollDisabled(isAltScreen)
                    .simultaneousGesture(
                        remoteScrollGesture,
                        including: isAltScreen && isConnected ? .all : .none
                    )
                    .onTapGesture { if isConnected { keyboardShown = true } }
                    .onPreferenceChange(PaneScrollContentFrameKey.self) { frame in
                        let shouldFollow = pinTracker.update(
                            contentTopOffset: frame.minY,
                            contentHeight: frame.height,
                            viewportHeight: viewport.size.height
                        )
                        if shouldFollow {
                            proxy.scrollTo("content", anchor: .bottom)
                        }
                    }
                }
            }
            // Dim stale content while disconnected so it's clearly not live.
            .opacity(isConnected ? 1 : 0.5)

            Divider()

            if !composition.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "character.cursor.ibeam")
                        .foregroundStyle(.secondary)
                    Text(composition)
                        .font(.system(size: 15))
                        .underline()
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
            }

            ControlKeyBarView(
                activeModifiers: $activeModifiers,
                onSpecialKey: sendSpecialKey
            )
            .disabled(!isConnected)

            TerminalKeyInput(
                isFocused: Binding(
                    get: { keyboardShown && isConnected },
                    set: { keyboardShown = $0 }
                ),
                onText: sendTypedText,
                onBackspace: sendBackspace,
                onComposition: { composition = $0 }
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: keyboardShown) {
            if !keyboardShown { composition = "" }
        }
        .onChange(of: isConnected) {
            // Drop the keyboard and any half-composed text on disconnect.
            if !isConnected {
                keyboardShown = false
                composition = ""
                activeModifiers = []
            } else {
                // A reconnect leaves this view on screen, so `onAppear`
                // won't fire again — but the Mac forgot the watch with the
                // old connection and has to be told again.
                client.watchPane(pane.id)
            }
        }
        // The pane closed on the Mac: pop back to the pane list. Only judged
        // against a snapshot from a live connection — a reconnect clears
        // `snapshot`, and that must not be read as "the pane is gone".
        .onChange(of: client.snapshot) {
            guard client.isConnected, let snapshot = client.snapshot else {
                return
            }
            if snapshot.pane(withID: pane.id) == nil { dismiss() }
        }
        .navigationTitle(currentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if client.supportsPaneSchedules {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSchedules = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .accessibilityLabel("Scheduled input")
                    .disabled(!isConnected)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectionSnapshot = SelectionSnapshot(
                        text: screen?.text ?? ""
                    )
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Select and copy text")
                .disabled(screen?.text.isEmpty != false)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    keyboardShown.toggle()
                } label: {
                    Image(
                        systemName: keyboardShown
                            ? "keyboard.chevron.compact.down"
                            : "keyboard"
                    )
                }
                .accessibilityLabel(
                    keyboardShown ? "Hide keyboard" : "Show keyboard"
                )
                .disabled(!isConnected)
            }
        }
        .sheet(item: $selectionSnapshot) { snapshot in
            PaneTextSelectionView(text: snapshot.text)
        }
        .sheet(isPresented: $showsSchedules) {
            PaneScheduleView(pane: pane, client: client)
        }
        .onAppear {
            rebuildRenderedChunks()
            client.watchPane(pane.id)
        }
        .onChange(of: screen) { rebuildRenderedChunks() }
        .onDisappear { client.unwatchPane(pane.id) }
    }

    private var disconnectedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 2) {
                Text(disconnectedTitle)
                    .font(.subheadline.weight(.semibold))
                Text("Input is disabled until reconnected.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            if client.state == .connecting {
                ProgressView()
                    .tint(.white)
            } else {
                Button("Reconnect") { client.reconnect() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.9))
    }

    private var disconnectedTitle: String {
        switch client.state {
        case .connecting: "Reconnecting…"
        case let .failed(message): "Disconnected — \(message)"
        default: "Disconnected"
        }
    }

    /// The pane's title follows the Mac (the running command changes it),
    /// falling back to the value captured at push while reconnecting.
    private var currentTitle: String {
        client.snapshot?.pane(withID: pane.id)?.title ?? pane.title
    }

    private var screen: RemoteClient.PaneScreen? {
        client.paneContent[pane.id]
    }

    private var isAltScreen: Bool {
        screen?.altScreen == true
    }

    /// Converts vertical drags into wheel lines for the Mac: dragging
    /// down reveals older content (positive deltaY), matching natural
    /// touch scrolling.
    private var remoteScrollGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let total = value.translation.height + remoteScrollRemainder
                let lines = (total / Self.remoteScrollLineHeight)
                    .rounded(.towardZero)
                if lines != 0 {
                    client.sendScroll(
                        paneID: pane.id,
                        deltaY: Double(lines)
                    )
                    remoteScrollRemainder = total
                        - lines * Self.remoteScrollLineHeight
                        - value.translation.height
                } else {
                    remoteScrollRemainder = total - value.translation.height
                }
            }
            .onEnded { _ in remoteScrollRemainder = 0 }
    }

    /// Lines per rendered chunk. Small enough that each `Text` stays well
    /// under the layer rasterization limit, large enough that text
    /// selection can still span a useful range.
    private static let chunkLineCount = 100

    /// Re-renders the pane text into `renderedChunks`, with per-cell colors
    /// from the Mac and the cursor cell rendered as an inverse block, like
    /// a terminal's block cursor. Colored lines are bottom-aligned to the
    /// plain text, so any top lines without styling fall back to the
    /// default color. The cell/cursor/run math is platform-neutral and
    /// lives in `RemotePaneScreenRenderer`; this view only maps its
    /// resolved RGB values to `Color`.
    private func rebuildRenderedChunks() {
        // Reconnecting drops `paneContent`; keep the last screen on display
        // (dimmed by the disconnected banner) instead of blanking the pane
        // until the Mac sends content again.
        guard let screen else {
            if renderedChunks.isEmpty { renderedChunks = [AttributedString(" ")] }
            return
        }
        guard !screen.text.isEmpty || screen.cursorRow != nil else {
            renderedChunks = [AttributedString(" ")]
            return
        }

        let lines = RemotePaneScreenRenderer.renderedLines(
            text: screen.text,
            cursorRow: screen.cursorRow,
            cursorColumn: screen.cursorColumn,
            styledLines: screen.styledLines
        )

        var chunks: [AttributedString] = []
        chunks.reserveCapacity(
            (lines.count + Self.chunkLineCount - 1) / Self.chunkLineCount
        )
        var current = AttributedString()
        for (index, runs) in lines.enumerated() {
            for run in runs {
                current += styledRun(run)
            }
            if (index + 1).isMultiple(of: Self.chunkLineCount)
                || index == lines.count - 1 {
                chunks.append(current)
                current = AttributedString()
            } else {
                current += AttributedString("\n")
            }
        }
        renderedChunks = chunks
    }

    private func styledRun(_ run: RemotePaneRun) -> AttributedString {
        var attributed = AttributedString(run.text)
        let foreground = run.foreground.map(Self.color(fromRGB:))
            ?? Color.primary
        let background = run.background.map(Self.color(fromRGB:))
        if run.inverse {
            attributed.foregroundColor = background ?? Color(.systemBackground)
            attributed.backgroundColor = run.foreground.map(Self.color(fromRGB:))
                ?? Color.primary
        } else {
            // Faint/dim text (SGR 2) renders at reduced intensity, matching
            // the Mac's dimmed hint text (e.g. Claude's "Brewed for …").
            attributed.foregroundColor = run.faint
                ? foreground.opacity(0.5)
                : foreground
            if let background { attributed.backgroundColor = background }
        }
        if run.bold {
            attributed.font = .system(size: 13, weight: .bold, design: .monospaced)
        }
        return attributed
    }

    private struct PaneScrollContentFrameKey: PreferenceKey {
        static let defaultValue = CGRect.zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            value = nextValue()
        }
    }

    private static func color(fromRGB rgb: Int) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    private func sendTypedText(_ text: String) {
        guard isConnected else { return }
        // The software keyboard's return key arrives as "\n". Injecting
        // "\r" as *text* makes TUIs treat it as a literal newline insert
        // rather than an Enter keypress, so route it through the
        // pressEnter flag, which the Mac delivers as a real key event.
        if text == "\n" {
            client.sendInput(paneID: pane.id, text: "", pressEnter: true)
            consumeModifiers()
            return
        }
        // With Ctrl/Option armed the keystroke must become a real key
        // event (Ctrl+C as injected text bytes is invisible to TUIs
        // using the kitty keyboard protocol).
        if activeModifiers.contains(.control)
            || activeModifiers.contains(.option) {
            for character in text {
                client.sendKey(
                    paneID: pane.id,
                    key: String(character),
                    modifiers: modifierNames
                )
            }
            consumeModifiers()
            return
        }
        client.sendInput(paneID: pane.id, text: text, pressEnter: false)
        consumeModifiers()
    }

    private func sendBackspace() {
        guard isConnected else { return }
        client.sendKey(
            paneID: pane.id,
            key: "delete",
            modifiers: modifierNames
        )
        consumeModifiers()
    }

    private func sendSpecialKey(_ key: ControlKey) {
        guard isConnected else { return }
        if key == .paste {
            pasteFromClipboard()
            return
        }
        // Shift+Tab is a single bar key (Claude Code cycles its permission
        // mode with it), but the wire format only knows "tab" plus a shift
        // modifier — "shiftTab" is not a named key on the Mac side. The Set
        // merge keeps "shift" from appearing twice when it is also armed.
        if key == .shiftTab {
            client.sendKey(
                paneID: pane.id,
                key: ControlKey.tab.rawValue,
                modifiers: Set(modifierNames + ["shift"]).sorted()
            )
            consumeModifiers()
            return
        }
        client.sendKey(
            paneID: pane.id,
            key: key.rawValue,
            modifiers: modifierNames
        )
        consumeModifiers()
    }

    /// The transport rejects frames over 1 MB (`RemoteFrameCodec`), and a
    /// paste that large would kill the connection — cap well below. An
    /// oversized clipboard is dropped whole rather than truncated: a
    /// partially pasted command is worse than nothing.
    private static let maxPasteBytes = 256 * 1024

    /// Sends the clipboard to the pane as pasted text. The Mac delivers it
    /// via `ghostty_surface_text`, which libghostty treats as a paste, so
    /// multi-line content is handled by the terminal's own paste path.
    private func pasteFromClipboard() {
        guard isConnected,
              let text = UIPasteboard.general.string,
              !text.isEmpty,
              text.utf8.count <= Self.maxPasteBytes
        else { return }
        client.sendInput(paneID: pane.id, text: text, pressEnter: false)
        consumeModifiers()
    }

    private var modifierNames: [String] {
        activeModifiers.filter(\.isModifier).map(\.rawValue).sorted()
    }

    /// Modifiers are one-shot: they apply to the next keystroke only,
    /// like sticky keys, so Ctrl stays lit just long enough to compose
    /// e.g. Ctrl+C.
    private func consumeModifiers() {
        activeModifiers = []
    }
}
