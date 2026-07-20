import MyTTYRemoteKit
import SwiftUI

struct RemoteAccessSettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var model: RemoteAccessSettingsModel
    let localizer: MyTTYLocalizer

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
                    Text(formattedCode(code.value))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .monospacedDigit()
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
                            model.generateCode()
                        }
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

    private func formattedCode(_ value: String) -> String {
        guard value.count == 6 else { return value }
        let midpoint = value.index(value.startIndex, offsetBy: 3)
        return "\(value[..<midpoint]) \(value[midpoint...])"
    }
}
