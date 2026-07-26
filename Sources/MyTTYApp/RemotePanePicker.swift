import AppKit
import MyTTYRemoteKit
import SwiftUI

/// What the user picked in the remote pane picker.
struct RemotePaneSelection: Equatable {
    let hostID: String
    let hostName: String
    let remotePaneID: String
    let title: String
}

/// Drives the picker: the paired Macs, the panes the selected one currently
/// has open, and the connection state while that list is still arriving.
///
/// Panes only become visible once a session to the host is up, so the list
/// starts empty and fills in. That is also why the picker connects on
/// selection rather than up front — browsing every paired Mac at once would
/// open a connection to each of them.
@MainActor
final class RemotePanePickerModel: ObservableObject {
    @Published private(set) var hosts: [PairedMac] = []
    @Published var selectedHostID: String? {
        didSet {
            guard selectedHostID != oldValue else { return }
            browseSelectedHost()
        }
    }

    @Published private(set) var panes: [(pane: RemotePane, tabTitle: String)] = []
    @Published private(set) var state: RemoteClient.ConnectionState = .disconnected

    private let connections: RemotePaneConnectionCoordinator

    init(connections: RemotePaneConnectionCoordinator) {
        self.connections = connections
        hosts = connections.hosts()
        selectedHostID = hosts.first?.deviceID
        browseSelectedHost()
    }

    var selectedHostName: String {
        hosts.first { $0.deviceID == selectedHostID }?.displayName ?? ""
    }

    func selection(forPaneID paneID: String) -> RemotePaneSelection? {
        guard let hostID = selectedHostID,
              let match = panes.first(where: { $0.pane.id == paneID })
        else { return nil }
        return RemotePaneSelection(
            hostID: hostID,
            hostName: selectedHostName,
            remotePaneID: match.pane.id,
            title: match.pane.title
        )
    }

    private func browseSelectedHost() {
        panes = []
        guard let hostID = selectedHostID else {
            state = .disconnected
            return
        }
        state = connections.connectionState(hostID: hostID)
        connections.browse(hostID: hostID) { [weak self] in
            guard let self else { return }
            self.panes = self.connections.availablePanes(hostID: hostID)
            self.state = self.connections.connectionState(hostID: hostID)
        }
    }
}

struct RemotePanePickerView: View {
    @ObservedObject var model: RemotePanePickerModel
    let localizer: MyTTYLocalizer
    let onPick: (RemotePaneSelection) -> Void
    let onCancel: () -> Void

    @State private var selectedPaneID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizer[.chooseRemotePane])
                .font(.headline)

            if model.hosts.isEmpty {
                Text(localizer[.noRemoteMacs])
                    .foregroundStyle(.secondary)
            } else {
                Picker(localizer[.remoteMacs], selection: $model.selectedHostID) {
                    ForEach(model.hosts) { host in
                        Text(
                            host.displayName.isEmpty
                                ? host.subtitle
                                : host.displayName
                        )
                        .tag(Optional(host.deviceID))
                    }
                }

                paneList
            }

            HStack {
                Spacer()
                Button(localizer[.cancel], action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(localizer[.openRemotePane]) {
                    guard let selectedPaneID,
                          let selection = model.selection(forPaneID: selectedPaneID)
                    else { return }
                    onPick(selection)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPaneID == nil)
            }
        }
        .padding(16)
        .frame(width: 420, height: 360)
    }

    @ViewBuilder
    private var paneList: some View {
        if model.panes.isEmpty {
            VStack(spacing: 8) {
                if model.state == .connecting {
                    ProgressView().controlSize(.small)
                    Text(localizer[.remoteConnecting])
                        .foregroundStyle(.secondary)
                } else if case let .failed(message) = model.state {
                    Text("\(localizer[.remoteDisconnected]) — \(message)")
                        .foregroundStyle(.red)
                } else {
                    Text(localizer[.noRemotePanesAvailable])
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedPaneID) {
                ForEach(model.panes, id: \.pane.id) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.pane.title.isEmpty
                            ? entry.tabTitle
                            : entry.pane.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(entry.pane.command)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(entry.pane.id)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// Presents `RemotePanePickerView` as a sheet on the window that asked for
/// a remote pane.
@MainActor
final class RemotePanePickerController {
    private var window: NSWindow?

    func present(
        connections: RemotePaneConnectionCoordinator,
        localizer: MyTTYLocalizer,
        over parent: NSWindow?,
        onPick: @escaping (RemotePaneSelection) -> Void
    ) {
        guard let parent else { return }
        let model = RemotePanePickerModel(connections: connections)
        let view = RemotePanePickerView(
            model: model,
            localizer: localizer,
            onPick: { [weak self] selection in
                self?.dismiss(from: parent)
                onPick(selection)
            },
            onCancel: { [weak self] in
                self?.dismiss(from: parent)
            }
        )
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.styleMask = [.titled]
        window = sheet
        parent.beginSheet(sheet)
    }

    private func dismiss(from parent: NSWindow) {
        guard let window else { return }
        parent.endSheet(window)
        self.window = nil
    }
}
