import MyTTYRemoteKit
import SwiftUI

private struct AddMacRoute: Hashable {}
private struct EditMacRoute: Hashable {
    let deviceID: String
}

/// A tapped notification still being navigated to. The Mac is kept
/// alongside the pane so the whole path — session, tab, pane — can be
/// rebuilt in a single assignment once a snapshot names where the pane
/// lives; appending to a stack whose push animation is still running is
/// how routes get silently dropped.
private struct PendingNotificationOpen {
    let mac: PairedMac
    let paneID: String?
}

struct RootView: View {
    @StateObject private var client = RemoteClient(
        pushRegistration: PushRegistration.shared
    )
    @State private var pairedMacs: [PairedMac] = PairedMacStore.loadAll()
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    /// Armed either when the app comes back to the foreground inside a
    /// session (so the connection iOS tore down while suspended is
    /// re-established), or when a live session simply drops while the app
    /// stays active. The first attempt often races the network still
    /// settling (Wi-Fi re-associates a moment later, so the connect fails
    /// instantly), so a failed attempt is retried a few times with a short
    /// delay — but only a bounded number, so an unreachable Mac doesn't
    /// spin in a retry loop.
    @State private var pendingAutoReconnect = false
    @State private var autoReconnectAttempts = 0
    @State private var autoReconnectRetryTask: Task<Void, Never>?
    private static let maxAutoReconnectAttempts = 3
    private static let autoReconnectRetryDelay: Duration = .seconds(2)
    @ObservedObject private var pushRegistration = PushRegistration.shared
    /// Surfaces the auto-reconnect loop above, which is otherwise
    /// invisible: the session UI underneath just shows a spinner or a
    /// stale screen while attempts fire in the background, so this is the
    /// only signal the user gets that something is retrying, or that it
    /// gave up and sent them back to Home.
    private enum ReconnectToast: Equatable {
        case reconnecting
        case disconnected(macName: String?)
    }
    @State private var toast: ReconnectToast?
    @State private var toastDismissTask: Task<Void, Never>?
    /// A tapped notification whose pane cannot be located yet, because
    /// the session it belongs to is still connecting. Resolved against
    /// the first snapshot that arrives.
    @State private var pendingNotificationOpen: PendingNotificationOpen?

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                pairedMacs: pairedMacs,
                onConnect: { mac in
                    // Asking for notification permission here rather than
                    // at first launch: the prompt only makes sense once
                    // there is a Mac that could push anything.
                    PushRegistration.shared.register()
                    client.connect(mac: mac)
                    path.append(mac)
                },
                onAddMac: { path.append(AddMacRoute()) },
                onEdit: { mac in
                    path.append(EditMacRoute(deviceID: mac.deviceID))
                },
                onDelete: { mac in
                    pairedMacs = PairedMacStore.remove(id: mac.deviceID)
                },
                onMove: { source, destination in
                    pairedMacs.move(fromOffsets: source, toOffset: destination)
                    PairedMacStore.replaceAll(pairedMacs)
                }
            )
            .navigationDestination(for: PairedMac.self) { mac in
                SessionView(mac: mac, client: client)
            }
            .navigationDestination(for: WindowRoute.self) { route in
                TabListView(windowID: route.windowID, client: client)
            }
            .navigationDestination(for: TabRoute.self) { route in
                PaneListView(tabID: route.tabID, client: client)
            }
            .navigationDestination(for: PaneRoute.self) { route in
                PaneRouteView(paneID: route.paneID, client: client)
            }
            .navigationDestination(for: AddMacRoute.self) { _ in
                PairingView(client: client) { mac in
                    pairedMacs = PairedMacStore.add(mac)
                    PushRegistration.shared.register()
                    path.removeLast()
                }
            }
            .navigationDestination(for: EditMacRoute.self) { route in
                // Resolved by ID at presentation time: the row index can
                // shift under an open editor when another device's list
                // change syncs in, and a deleted Mac simply has no editor.
                if let index = pairedMacs.firstIndex(where: {
                    $0.deviceID == route.deviceID
                }) {
                    PairedMacEditView(mac: $pairedMacs[index]) {
                        PairedMacStore.replaceAll(pairedMacs)
                    }
                }
            }
        }
        // A toast overlay rather than anything inline in the pushed views:
        // the drop can happen on any screen in the stack (tab list, pane
        // list, pane detail), and the retry/give-up story is the same no
        // matter where it caught the user.
        .overlay(alignment: .bottom) {
            if let toast {
                reconnectToastView(toast)
                    .transition(
                        .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toast)
        // SessionView and everything pushed below it (tabs, panes, pane
        // detail) all share this one stack, so their own onAppear/
        // onDisappear fire on every push/pop within the mac's session —
        // not just when actually entering or leaving it. Only disconnect
        // once the path empties back out to Home.
        .onChange(of: path.count) { oldCount, newCount in
            if newCount == 0 && oldCount > 0 {
                client.disconnect()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                autoReconnectAttempts = 0
                pendingAutoReconnect = !path.isEmpty
                autoReconnectIfNeeded()
            case .background:
                pendingAutoReconnect = false
                autoReconnectRetryTask?.cancel()
                autoReconnectRetryTask = nil
                autoReconnectAttempts = 0
                if toast == .reconnecting {
                    toast = nil
                }
                toastDismissTask?.cancel()
                toastDismissTask = nil
            default:
                break
            }
        }
        // The connection often still looks alive the instant the app
        // resumes and only fails a moment later, so the armed reconnect is
        // re-evaluated on every state change too. A session that was live
        // and then drops on its own — as opposed to the deliberate
        // disconnect from navigating back to Home, which the path.count
        // handler above already covers — gets armed here too.
        .onChange(of: client.state) { oldValue, newValue in
            if oldValue == .connected, !path.isEmpty {
                switch newValue {
                case .disconnected, .failed:
                    autoReconnectAttempts = 0
                    pendingAutoReconnect = true
                case .connecting, .connected:
                    break
                }
            }
            autoReconnectIfNeeded()
        }
        .onChange(of: pushRegistration.pendingOpen) { openTappedNotification() }
        .onAppear { openTappedNotification() }
        // The pane cannot be located until the Mac has sent a snapshot,
        // which is always after the tap; finish the navigation then.
        .onChange(of: client.snapshot) { openPendingPaneIfPossible() }
    }

    /// A rounded, non-interactive banner for the auto-reconnect states —
    /// there is nothing to tap, so it never competes with the screen
    /// underneath for input.
    @ViewBuilder
    private func reconnectToastView(_ toast: ReconnectToast) -> some View {
        HStack(spacing: 8) {
            switch toast {
            case .reconnecting:
                ProgressView()
                    .tint(.white)
                Text("Reconnecting…")
            case .disconnected(let macName):
                Image(systemName: "wifi.slash")
                Text(
                    macName.map { "Disconnected from \($0)" }
                        ?? "Disconnected"
                )
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.8), in: Capsule())
        .padding(.bottom, 24)
        .allowsHitTesting(false)
    }

    /// Navigates to what a tapped Attention notification points at:
    /// connect to the Mac that sent it, then descend to the pane once the
    /// snapshot names where it lives.
    private func openTappedNotification() {
        guard let target = pushRegistration.pendingOpen else { return }
        pushRegistration.pendingOpen = nil

        guard let mac = pairedMacs.first(where: {
            $0.deviceID == target.macID
        }) else { return }

        switch PushOpenConnectPolicy.action(
            targetMacID: mac.deviceID,
            connectedMacID: client.connectedMacID,
            isConnected: client.isConnected
        ) {
        case .connect:
            client.connect(mac: mac)
        case .reuseButArmReconnect:
            // A session that survived backgrounding often only reports its
            // death a moment after the app resumes — by which time the
            // scene-phase handler has already run and found nothing to
            // arm. Arm it here so a stale connection heals instead of
            // leaving the pane spinning forever.
            autoReconnectAttempts = 0
            pendingAutoReconnect = true
        }
        pendingNotificationOpen = PendingNotificationOpen(
            mac: mac,
            paneID: target.paneID
        )
        path = NavigationPath()
        path.append(mac)
        openPendingPaneIfPossible()
    }

    private func openPendingPaneIfPossible() {
        guard let pending = pendingNotificationOpen,
              let snapshot = client.snapshot
        else { return }
        // The user connected to a different Mac while this open was still
        // waiting; the tap's intent is stale, not worth hijacking the
        // session they chose.
        guard client.connectedMacID == pending.mac.deviceID else {
            pendingNotificationOpen = nil
            return
        }
        // Without a pane to descend to (the push arrived undecrypted),
        // the session root already on the path is the destination.
        guard let paneID = pending.paneID else {
            pendingNotificationOpen = nil
            return
        }
        // Not in this snapshot — which may be a stale one from before the
        // app was suspended. Keep waiting; the reconnect armed by the tap
        // delivers a fresh snapshot, and a pane closed on the Mac simply
        // leaves the session root showing.
        guard let steps = snapshot.paneOpenSteps(toPaneID: paneID)
        else { return }
        pendingNotificationOpen = nil

        // Rebuilding the path in one assignment rather than appending to
        // the stack already animating its way into the session: appends
        // landing mid-transition are silently dropped, which stranded
        // notification taps on the tab list.
        var rebuilt = NavigationPath()
        rebuilt.append(pending.mac)
        for step in steps {
            switch step {
            case .window(let id):
                rebuilt.append(WindowRoute(windowID: id))
            case .tab(let id):
                rebuilt.append(TabRoute(tabID: id))
            case .pane(let id):
                rebuilt.append(PaneRoute(paneID: id))
            }
        }
        path = rebuilt
    }

    private func autoReconnectIfNeeded() {
        guard pendingAutoReconnect,
              scenePhase == .active,
              !path.isEmpty,
              client.canReconnect
        else { return }
        switch client.state {
        case .connected:
            // Reconnected (or the stale session turned out alive): done.
            pendingAutoReconnect = false
            autoReconnectAttempts = 0
            if toast == .reconnecting {
                toast = nil
            }
        case .connecting:
            break
        case .disconnected, .failed:
            guard autoReconnectRetryTask == nil else { return }
            guard
                autoReconnectAttempts < Self.maxAutoReconnectAttempts
            else {
                // Out of attempts: rather than leave the pane stuck on a
                // dead session showing only its own Reconnect button, bail
                // all the way out to Mac selection and say so — a toast
                // that outlives the pop, since the screen it would have
                // sat on is gone.
                pendingAutoReconnect = false
                let macName = client.connectedMacDisplayName
                toast = .disconnected(macName: macName)
                path = NavigationPath()
                scheduleToastDismiss(for: .disconnected(macName: macName))
                return
            }
            toast = .reconnecting
            toastDismissTask?.cancel()
            toastDismissTask = nil
            autoReconnectAttempts += 1
            // The first attempt fires immediately; later ones wait out the
            // window where the network is still coming back after resume.
            let delay: Duration =
                autoReconnectAttempts == 1
                ? .zero : Self.autoReconnectRetryDelay
            autoReconnectRetryTask = Task {
                if delay > .zero { try? await Task.sleep(for: delay) }
                autoReconnectRetryTask = nil
                guard !Task.isCancelled,
                      pendingAutoReconnect,
                      scenePhase == .active,
                      !path.isEmpty,
                      client.canReconnect
                else { return }
                switch client.state {
                case .disconnected, .failed:
                    client.reconnect()
                case .connecting, .connected:
                    break
                }
            }
        }
    }

    /// Clears the "gave up" toast a few seconds after it appears, but only
    /// if it is still the same toast — a fresh connect attempt (from the
    /// user picking a Mac again) may have already replaced it with
    /// something else by the time this fires.
    private func scheduleToastDismiss(for shown: ReconnectToast) {
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, toast == shown else { return }
            toast = nil
        }
    }
}
