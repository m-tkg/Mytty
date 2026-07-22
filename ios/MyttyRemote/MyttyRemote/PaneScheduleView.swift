import MyTTYRemoteKit
import SwiftUI

/// Lets the phone view, create, and delete the Mac's scheduled inputs for
/// one pane — the remote counterpart to the Mac's own scheduled-input
/// dialog. The Mac is the source of truth: this view only ever shows what
/// `client.paneSchedules` last reported and asks for a fresh copy after
/// every create/delete.
struct PaneScheduleView: View {
    let pane: RemotePane
    @ObservedObject var client: RemoteClient

    @Environment(\.dismiss) private var dismiss
    @State private var fireAt = Date.now.addingTimeInterval(60)
    @State private var text = ""
    @State private var pressEnter = true

    private var schedules: [RemotePaneSchedule] {
        client.paneSchedules[pane.id] ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section("New schedule") {
                    DatePicker(
                        "Time",
                        selection: $fireAt,
                        in: Date.now...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField("Text to send", text: $text, axis: .vertical)
                    Toggle("Press Enter", isOn: $pressEnter)
                    Button("Schedule") {
                        client.createPaneSchedule(
                            paneID: pane.id,
                            fireAt: fireAt,
                            text: text,
                            pressEnter: pressEnter
                        )
                        text = ""
                        fireAt = Date.now.addingTimeInterval(60)
                    }
                    .disabled(!client.isConnected)
                }

                Section("Scheduled") {
                    if schedules.isEmpty {
                        Text("No scheduled input.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(schedules) { schedule in
                            scheduleRow(schedule)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        client.deletePaneSchedule(
                                            paneID: pane.id,
                                            scheduleID: schedule.id
                                        )
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Scheduled Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { client.requestPaneSchedules(paneID: pane.id) }
    }

    private func scheduleRow(_ schedule: RemotePaneSchedule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                schedule.fireAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if schedule.pressEnter {
                    Image(systemName: "return")
                        .foregroundStyle(.secondary)
                }
                Text(
                    schedule.text.isEmpty
                        ? "⏎ Enter only"
                        : schedule.text
                )
                .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}
