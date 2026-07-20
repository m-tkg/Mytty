import SwiftUI

struct DeviceSettingsView: View {
    @Binding var pairedMacs: [PairedMac]

    var body: some View {
        List {
            if pairedMacs.isEmpty {
                Text("No Macs are paired yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Registered Macs") {
                    ForEach($pairedMacs) { $mac in
                        NavigationLink {
                            PairedMacEditView(mac: $mac) {
                                PairedMacStore.replaceAll(pairedMacs)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mac.displayName)
                                if !mac.subtitle.isEmpty {
                                    Text(mac.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: remove)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func remove(at offsets: IndexSet) {
        let idsToRemove = offsets.map { pairedMacs[$0].deviceID }
        var updated = pairedMacs
        for id in idsToRemove {
            updated = PairedMacStore.remove(id: id)
        }
        pairedMacs = updated
    }
}
