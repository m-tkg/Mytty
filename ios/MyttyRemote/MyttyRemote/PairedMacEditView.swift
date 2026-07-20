import SwiftUI

/// Edits one paired Mac's label and how to reach it: the Bonjour service
/// name, or a manual host and port. Pairing credentials are not editable —
/// re-pair to change those.
struct PairedMacEditView: View {
    @Binding var mac: PairedMac
    /// Called after the edited values are written back, so the owner can
    /// persist the full list.
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var connection: ConnectionMethod
    @State private var serviceName: String
    @State private var host: String
    @State private var portText: String

    enum ConnectionMethod: Hashable {
        case bonjour
        case direct
    }

    init(mac: Binding<PairedMac>, onSave: @escaping () -> Void) {
        _mac = mac
        self.onSave = onSave
        let value = mac.wrappedValue
        _displayName = State(initialValue: value.displayName)
        _connection = State(
            initialValue: value.macName.isEmpty ? .direct : .bonjour
        )
        _serviceName = State(initialValue: value.macName)
        _host = State(initialValue: value.manualHost ?? "")
        _portText = State(
            initialValue: value.manualPort.map(String.init) ?? ""
        )
    }

    var body: some View {
        Form {
            Section("Label") {
                TextField("Label", text: $displayName)
            }

            Section {
                Picker("Connection", selection: $connection) {
                    Text("Bonjour").tag(ConnectionMethod.bonjour)
                    Text("Host & Port").tag(ConnectionMethod.direct)
                }
                .pickerStyle(.segmented)

                switch connection {
                case .bonjour:
                    TextField("Service name", text: $serviceName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                case .direct:
                    TextField("Host (e.g. 192.168.1.10)", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text(footerText)
            }
        }
        .navigationTitle("Edit Mac")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
    }

    private var footerText: String {
        switch connection {
        case .bonjour:
            "Reconnects by finding this service name on the local network. "
                + "It must match the name the Mac advertises."
        case .direct:
            "Reconnects to this address directly. Use it when Bonjour "
                + "discovery does not work across your network."
        }
    }

    private var isValid: Bool {
        switch connection {
        case .bonjour:
            return !trimmedServiceName.isEmpty
        case .direct:
            return !trimmedHost.isEmpty && parsedPort != nil
        }
    }

    private var trimmedServiceName: String {
        serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedPort: UInt16? {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = UInt16(trimmed), value > 0 else { return nil }
        return value
    }

    private func save() {
        var updated = mac
        let trimmedName = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch connection {
        case .bonjour:
            // A non-empty service name takes precedence on reconnect; the
            // manual address is kept as-is so switching back is lossless.
            updated.macName = trimmedServiceName
        case .direct:
            guard let port = parsedPort else { return }
            updated.macName = ""
            updated.manualHost = trimmedHost
            updated.manualPort = port
        }
        updated.displayName = trimmedName.isEmpty
            ? fallbackLabel(for: updated)
            : trimmedName
        mac = updated
        onSave()
        dismiss()
    }

    private func fallbackLabel(for mac: PairedMac) -> String {
        !mac.macName.isEmpty ? mac.macName : (mac.manualHost ?? "Mac")
    }
}
