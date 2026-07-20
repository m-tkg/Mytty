import SwiftUI

struct HomeView: View {
    let pairedMacs: [PairedMac]
    let onConnect: (PairedMac) -> Void
    let onAddMac: () -> Void

    var body: some View {
        List {
            if !pairedMacs.isEmpty {
                Section("Your Macs") {
                    ForEach(pairedMacs) { mac in
                        Button {
                            onConnect(mac)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mac.displayName)
                                        .foregroundStyle(.primary)
                                    if !mac.subtitle.isEmpty {
                                        Text(mac.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    onAddMac()
                } label: {
                    Label("Add a Mac", systemImage: "plus.circle")
                }
            }

            if pairedMacs.isEmpty {
                Section {
                    Text("Pair with a Mac running Mytty to view and control its terminal panes from here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Mytty")
    }
}
