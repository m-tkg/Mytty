import MyTTYRemoteKit
import SwiftUI

private struct AddMacRoute: Hashable {}
private struct DeviceSettingsRoute: Hashable {}

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
    @StateObject private var client = RemoteClient()
    @State private var pairedMacs: [PairedMac] = PairedMacStore.loadAll()
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    /// Armed when the app comes back to the foreground inside a session, so
    /// the connection iOS tore down while suspended is re-established once
    /// — and only once, so an unreachable Mac doesn't spin in a retry loop.
    @State private var pendingForegroundReconnect = false
    @ObservedObject private var pushRegistration = PushRegistration.shared
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
                onAddMac: { path.append(AddMacRoute()) }
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(DeviceSettingsRoute())
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
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
            .navigationDestination(for: DeviceSettingsRoute.self) { _ in
                DeviceSettingsView(pairedMacs: $pairedMacs)
            }
        }
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
                pendingForegroundReconnect = !path.isEmpty
                reconnectAfterForegroundIfNeeded()
            case .background:
                pendingForegroundReconnect = false
            default:
                break
            }
        }
        // The connection often still looks alive the instant the app
        // resumes and only fails a moment later, so the armed reconnect is
        // re-evaluated on every state change too.
        .onChange(of: client.state) { reconnectAfterForegroundIfNeeded() }
        .onChange(of: pushRegistration.pendingOpen) { openTappedNotification() }
        .onAppear { openTappedNotification() }
        // The pane cannot be located until the Mac has sent a snapshot,
        // which is always after the tap; finish the navigation then.
        .onChange(of: client.snapshot) { openPendingPaneIfPossible() }
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
            pendingForegroundReconnect = true
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

    private func reconnectAfterForegroundIfNeeded() {
        guard pendingForegroundReconnect,
              scenePhase == .active,
              !path.isEmpty,
              client.canReconnect
        else { return }
        switch client.state {
        case .disconnected, .failed:
            pendingForegroundReconnect = false
            client.reconnect()
        case .connecting, .connected:
            break
        }
    }
}
