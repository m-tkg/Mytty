import MyTTYRemoteKit
import SwiftUI

/// Navigation below a Mac's session is addressed by ID rather than by
/// pushing a view directly, so the whole path can also be built from
/// nothing but the pane ID an Attention push carries. Every level
/// re-resolves against the newest snapshot anyway, so carrying the ID is
/// no loss.
struct WindowRoute: Hashable {
    let windowID: String
}

struct TabRoute: Hashable {
    let tabID: String
}

struct PaneRoute: Hashable {
    let paneID: String
}

struct SessionView: View {
    let mac: PairedMac
    @ObservedObject var client: RemoteClient

    var body: some View {
        content
            .navigationTitle(mac.displayName)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch client.state {
        case .disconnected, .connecting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Connecting to \(mac.displayName)…")
                    .foregroundStyle(.secondary)
            }
        case let .failed(message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Could not connect")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") { client.connect(mac: mac) }
            }
            .multilineTextAlignment(.center)
            .padding()
        case .connected:
            WindowListView(client: client)
        }
    }
}

private struct WindowListView: View {
    @ObservedObject var client: RemoteClient

    var body: some View {
        let windows = client.snapshot?.windows ?? []
        Group {
            if windows.isEmpty {
                Text("No windows are open on your Mac.")
                    .foregroundStyle(.secondary)
            } else if windows.count == 1 {
                TabListView(windowID: windows[0].id, client: client)
            } else {
                List(windows) { window in
                    NavigationLink(
                        windowTitle(window),
                        value: WindowRoute(windowID: window.id)
                    )
                }
            }
        }
    }

    private func windowTitle(_ window: RemoteWindow) -> String {
        "Window (\(window.tabs.count) tabs)"
    }
}

struct TabListView: View {
    let windowID: String
    @ObservedObject var client: RemoteClient

    /// Re-resolved by ID so the list follows tabs opening and closing on
    /// the Mac instead of showing what was current when it was pushed.
    private var window: RemoteWindow? {
        client.snapshot?.window(withID: windowID)
    }

    var body: some View {
        List(window?.tabs ?? []) { tab in
            NavigationLink(value: TabRoute(tabID: tab.id)) {
                VStack(alignment: .leading) {
                    Text(tab.title)
                    Text("\(tab.panes.count) panes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Tabs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    client.newTab(windowID: windowID)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Tab")
            }
        }
    }
}

struct PaneListView: View {
    let tabID: String
    @ObservedObject var client: RemoteClient
    @Environment(\.dismiss) private var dismiss

    private var tab: RemoteTab? {
        client.snapshot?.tab(withID: tabID)
    }

    var body: some View {
        List(tab?.panes ?? []) { pane in
            NavigationLink(value: PaneRoute(paneID: pane.id)) {
                HStack {
                    Image(systemName: pane.kind == .terminal ? "terminal" : "safari")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(pane.command)
                        Text(pane.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if pane.isActive {
                        Spacer()
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle(tab?.title ?? "Panes")
        // The tab closed on the Mac: pop back to the tab list. Only judged
        // against a snapshot from a live connection — a reconnect clears
        // `snapshot`, and that must not be read as "the tab is gone".
        .onChange(of: client.snapshot) {
            guard client.isConnected, let snapshot = client.snapshot else {
                return
            }
            if snapshot.tab(withID: tabID) == nil { dismiss() }
        }
    }
}

/// Resolves the pane by ID before choosing which detail view to show, so
/// a route restored from a notification lands on the right one.
struct PaneRouteView: View {
    let paneID: String
    @ObservedObject var client: RemoteClient

    var body: some View {
        if let pane = client.snapshot?.pane(withID: paneID) {
            if pane.kind == .browser {
                BrowserPaneDetailView(pane: pane, client: client)
            } else {
                PaneDetailView(pane: pane, client: client)
            }
        } else {
            // Reached while reconnecting, or after the pane closed on the
            // Mac. The detail views handle the disconnected case
            // themselves once a snapshot arrives.
            ProgressView()
        }
    }
}
