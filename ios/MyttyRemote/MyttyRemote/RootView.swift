import SwiftUI

private struct AddMacRoute: Hashable {}
private struct DeviceSettingsRoute: Hashable {}

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
    @State private var pendingPaneOpen: String?

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

        // Re-connecting to the Mac already shown would drop a working
        // session and lose the pane content on screen.
        if client.connectedMacID != mac.deviceID || !client.isConnected {
            client.connect(mac: mac)
        }
        path = NavigationPath()
        path.append(mac)
        pendingPaneOpen = target.paneID
        openPendingPaneIfPossible()
    }

    private func openPendingPaneIfPossible() {
        guard let paneID = pendingPaneOpen,
              let snapshot = client.snapshot,
              let location = snapshot.location(ofPaneID: paneID)
        else { return }
        pendingPaneOpen = nil

        // A single window is shown as its tab list directly, with no
        // window level in the stack, so the path has to match that.
        if snapshot.windows.count > 1 {
            path.append(WindowRoute(windowID: location.windowID))
        }
        path.append(TabRoute(tabID: location.tabID))
        path.append(PaneRoute(paneID: location.paneID))
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
