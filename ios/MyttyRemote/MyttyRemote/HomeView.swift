import MyTTYRemoteKit
import SwiftUI

struct HomeView: View {
    let pairedMacs: [PairedMac]
    let onConnect: (PairedMac) -> Void
    let onAddMac: () -> Void
    let onEdit: (PairedMac) -> Void
    let onDelete: (PairedMac) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        List {
            if !pairedMacs.isEmpty {
                Section("Your Macs") {
                    ForEach(pairedMacs) { mac in
                        Button {
                            onConnect(mac)
                        } label: {
                            HStack(spacing: 12) {
                                // Affordance for the long-press drag that
                                // reorders the list; the gesture itself is
                                // the List's own, from onMove below.
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(mac)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                onEdit(mac)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
                    .onMove { source, destination in
                        onMove(source, destination)
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
