import AppKit
import MyTTYRemoteKit
import SwiftUI

struct RemoteAccessSettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var model: RemoteAccessSettingsModel
    @ObservedObject var remoteMacs: RemoteMacsSettingsModel
    let localizer: MyTTYLocalizer
    let onOpenRemotePane: (PairedMac) -> Void

    @State private var copiedLink = false
    @State private var pendingRemoval: RemotePairedDevice?
    @State private var pendingRename: RemotePairedDevice?
    @State private var renameDraft = ""

    var body: some View {
        Form {
            Section {
                enableRow
            }

            if settings.application.remoteAccessEnabled {
                Section(localizer[.pairingCode]) {
                    pairingRow
                }

                Section(localizer[.pairedDevices]) {
                    if model.pairedDevices.isEmpty {
                        Text(localizer[.noPairedDevices])
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.pairedDevices) { device in
                            deviceRow(device)
                        }
                    }
                }

                Section(localizer[.pushNotifications]) {
                    pushEnableRow
                }
            }

            // The client half — the Macs this Mac opens panes onto — lives
            // on the same pane because both directions share the one
            // pairing-link flow, and does not depend on this Mac's own
            // server being enabled.
            RemoteMacsSettingsSections(
                model: remoteMacs,
                localizer: localizer,
                onOpenPane: onOpenRemotePane
            )
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { model.refresh() }
        .alert(
            localizer[.removeDeviceQuestion],
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented { pendingRemoval = nil }
                }
            ),
            presenting: pendingRemoval
        ) { device in
            Button(localizer[.removeDevice], role: .destructive) {
                model.removeDevice(device)
            }
            Button(localizer[.cancel], role: .cancel) {}
        } message: { _ in
            Text(localizer[.removeDeviceWarning])
        }
        .alert(
            localizer[.renameDeviceQuestion],
            isPresented: Binding(
                get: { pendingRename != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRename = nil
                        renameDraft = ""
                    }
                }
            ),
            presenting: pendingRename
        ) { device in
            TextField(localizer[.deviceName], text: $renameDraft)
            Button(localizer[.renameDevice]) {
                model.renameDevice(device, name: renameDraft)
                renameDraft = ""
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(localizer[.cancel], role: .cancel) {}
        }
    }

    private var enableRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer[.enableRemoteAccess])
                    .font(.system(size: 13, weight: .semibold))
                Text(localizer[.remoteAccessDescription])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { settings.application.remoteAccessEnabled },
                    set: { enabled in
                        settings.updateApplication {
                            $0.remoteAccessEnabled = enabled
                        }
                        model.refresh()
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(localizer[.enableRemoteAccess])
        }
        .padding(.vertical, 4)
    }

    private var pushEnableRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer[.enablePushNotifications])
                    .font(.system(size: 13, weight: .semibold))
                Text(localizer[.pushNotificationsDescription])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: {
                        settings.application.remotePushNotificationsEnabled
                    },
                    set: { enabled in
                        settings.updateApplication {
                            $0.remotePushNotificationsEnabled = enabled
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(localizer[.enablePushNotifications])
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var pairingRow: some View {
        if let code = model.activeCode {
            TimelineView(.periodic(from: code.generatedAt, by: 1)) { context in
                let remaining = max(
                    0,
                    Int(code.expiresAt.timeIntervalSince(context.date).rounded(.up))
                )
                VStack(alignment: .leading, spacing: 8) {
                    RemotePairingQRCodeView(
                        payload: RemotePairingPayload(token: code.value).urlString()
                    )
                    if remaining > 0 {
                        Text(localizer.pairingCodeExpiresIn(seconds: remaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(localizer[.pairingCodeInstructions])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(localizer[.pairingCodeExpired])
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let port = model.listeningPort {
                        Text(localizer.listeningOnPort(Int(port)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(localizer[.generatePairingCode]) {
                            copiedLink = false
                            model.generateCode()
                        }
                        // A Mac pairing with this one has no camera in the
                        // loop, so it needs the same token as text.
                        Button(
                            copiedLink
                                ? localizer[.pairingLinkCopied]
                                : localizer[.copyPairingLink]
                        ) {
                            copyPairingLink(code.value)
                        }
                        .disabled(remaining == 0)
                        Button(localizer[.cancelPairing]) {
                            model.cancelPairing()
                        }
                    }
                }
            }
        } else {
            Button(localizer[.generatePairingCode]) {
                model.generateCode()
            }
        }
    }

    /// Puts the pairing token on the clipboard as the same
    /// `mytty://pair?...` URL the QR code encodes, so another Mac can paste
    /// it in Settings › Remote Macs.
    private func copyPairingLink(_ token: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            RemotePairingPayload(token: token).urlString(),
            forType: .string
        )
        copiedLink = true
    }

    private func deviceRow(_ device: RemotePairedDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                Text(localizer.pairedOnDate(
                    device.pairedAt.formatted(date: .abbreviated, time: .shortened)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    device.pushRelayID == nil
                        ? localizer[.devicePushNotRegistered]
                        : localizer[.devicePushRegistered]
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(localizer[.renameDevice]) {
                renameDraft = device.name
                pendingRename = device
            }
            .buttonStyle(.borderless)
            Button(localizer[.removeDevice]) {
                pendingRemoval = device
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }
}
