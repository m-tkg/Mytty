import MyTTYRemoteKit
import SwiftUI

/// The sections for the Macs this Mac opens remote panes onto — the client
/// half of remote access. Rendered inside `RemoteAccessSettingsView`'s Form
/// (the server half: the devices allowed to connect *in*), so both
/// directions of pairing live on the one Remote Access settings pane.
struct RemoteMacsSettingsSections: View {
    @ObservedObject var model: RemoteMacsSettingsModel
    let localizer: MyTTYLocalizer

    @State private var isAdding = false
    @State private var link = ""
    @State private var label = ""
    @State private var selectedMacID: String?
    @State private var manualHost = ""
    @State private var manualPort = "51735"
    @State private var pendingRemoval: PairedMac?
    @State private var pendingRename: PairedMac?
    @State private var renameDraft = ""

    var body: some View {
        Group {
            Section {
                header
            }

            Section(localizer[.remoteMacs]) {
                if model.hosts.isEmpty {
                    Text(localizer[.noRemoteMacs])
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.hosts) { host in
                        hostRow(host)
                    }
                }
                Button(localizer[.addRemoteMac]) {
                    isAdding = true
                }
            }

            if isAdding {
                Section(localizer[.pairingLink]) {
                    addForm
                }
            }
        }
        .onAppear { model.refresh() }
        .onDisappear { model.stopDiscovery() }
        .onChange(of: isAdding) {
            if isAdding {
                model.startDiscovery()
            } else {
                model.stopDiscovery()
                model.cancelPairing()
                link = ""
                label = ""
                selectedMacID = nil
            }
        }
        .onChange(of: model.pairingState) {
            // Close the form the moment a pairing lands, so the new Mac
            // appears in the list above without an extra click.
            if model.pairingState == .idle, !model.hosts.isEmpty, isAdding,
               !link.isEmpty {
                isAdding = false
            }
        }
        .alert(
            localizer[.removeRemoteMacQuestion],
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { host in
            Button(localizer[.removeRemoteMac], role: .destructive) {
                model.remove(host)
            }
            Button(localizer[.cancel], role: .cancel) {}
        } message: { _ in
            Text(localizer[.removeRemoteMacWarning])
        }
        .alert(
            localizer[.renameDeviceQuestion],
            isPresented: Binding(
                get: { pendingRename != nil },
                set: {
                    if !$0 {
                        pendingRename = nil
                        renameDraft = ""
                    }
                }
            ),
            presenting: pendingRename
        ) { host in
            TextField(localizer[.remoteMacName], text: $renameDraft)
            Button(localizer[.renameDevice]) {
                model.rename(host, to: renameDraft)
                renameDraft = ""
            }
            .disabled(
                renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
            Button(localizer[.cancel], role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(localizer[.remoteMacs])
                    .font(.system(size: 13, weight: .semibold))
                Text(localizer[.remoteMacsDescription])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func hostRow(_ host: PairedMac) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName.isEmpty ? host.subtitle : host.displayName)
                    .font(.system(size: 13, weight: .medium))
                if !host.subtitle.isEmpty {
                    Text(host.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(localizer[.renameDevice]) {
                renameDraft = host.displayName
                pendingRename = host
            }
            .buttonStyle(.borderless)
            Button(localizer[.removeRemoteMac]) {
                pendingRemoval = host
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var addForm: some View {
        Text(localizer[.pairingLinkInstructions])
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        TextField(localizer[.pairingLink], text: $link)
            .textFieldStyle(.roundedBorder)
        TextField(localizer[.remoteMacName], text: $label)
            .textFieldStyle(.roundedBorder)

        Picker(localizer[.remoteMacAddress], selection: $selectedMacID) {
            ForEach(model.discovered) { mac in
                Text(mac.name).tag(Optional(mac.id))
            }
            Text(localizer[.remoteMacAddress]).tag(String?.none)
        }

        if selectedMacID == nil {
            HStack {
                TextField("192.168.1.10", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                TextField("51735", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
        }

        if case let .failed(reason) = model.pairingState {
            Text(failureMessage(reason))
                .font(.caption)
                .foregroundStyle(.red)
        }

        HStack {
            if model.pairingState == .pairing {
                ProgressView().controlSize(.small)
                Button(localizer[.cancelPairing]) { model.cancelPairing() }
            } else {
                Button(localizer[.pairWithMac]) { startPairing() }
                    .disabled(link.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                Button(localizer[.cancel]) { isAdding = false }
            }
        }
    }

    private func startPairing() {
        let endpoint: RemoteMacsSettingsModel.PairingEndpoint
        if let selectedMacID,
           let mac = model.discovered.first(where: { $0.id == selectedMacID }) {
            endpoint = .bonjour(mac)
        } else {
            endpoint = .address(
                host: manualHost.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                port: UInt16(manualPort) ?? 0
            )
        }
        model.pair(link: link, endpoint: endpoint, label: label)
    }

    private func failureMessage(_ reason: String) -> String {
        switch RemoteMacsSettingsModel.RemotePairingFailure(rawValue: reason) {
        case .invalidLink, .noAddress:
            "\(localizer[.pairingFailed]) — \(localizer[.pairingLinkInstructions])"
        default:
            localizer[.pairingFailed]
        }
    }
}
