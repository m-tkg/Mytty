import Network
import SwiftUI
import UIKit

private enum AddressMethod: String, CaseIterable, Identifiable {
    case discovered = "On My Network"
    case manual = "Enter Address"

    var id: Self { self }
}

struct PairingView: View {
    @ObservedObject var client: RemoteClient
    let onPaired: (PairedMac) -> Void

    @StateObject private var discovery = MacDiscovery()
    @State private var method: AddressMethod = .discovered
    @State private var label = ""
    @State private var code = ""
    @State private var manualHost = ""
    @State private var manualPort = "51820"
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var selectedMac: DiscoveredMac?

    var body: some View {
        Form {
            Section {
                Picker("Address", selection: $method) {
                    ForEach(AddressMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch method {
            case .discovered:
                Section("Your Mac") {
                    if discovery.discovered.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Looking for Macs on your network…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(discovery.discovered) { mac in
                            Button {
                                selectedMac = mac
                                if label.isEmpty { label = mac.name }
                            } label: {
                                HStack {
                                    Text(mac.name)
                                    Spacer()
                                    if selectedMac?.id == mac.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            case .manual:
                Section("Address") {
                    TextField("Host or IP address", text: $manualHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                }
            }

            Section("Label") {
                TextField("e.g. My MacBook Pro", text: $label)
                    .textInputAutocapitalization(.words)
            }

            Section("Pairing Code") {
                TextField("6-digit code from Mytty on your Mac", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if isPairing {
                    HStack {
                        ProgressView()
                        Text("Connecting…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .cancel) {
                            client.cancelPairing()
                        }
                    }
                } else {
                    Button {
                        pair()
                    } label: {
                        Text("Pair")
                    }
                    .disabled(!canPair)
                }
            }
        }
        .navigationTitle("Add a Mac")
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private var canPair: Bool {
        guard code.count == 6 else { return false }
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        switch method {
        case .discovered: return selectedMac != nil
        case .manual: return !manualHost.isEmpty
        }
    }

    private func pair() {
        errorMessage = nil
        isPairing = true
        let deviceName = UIDevice.current.name
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let mac: PairedMac
                switch method {
                case .discovered:
                    guard let selectedMac else { return }
                    mac = try await client.pair(
                        macName: selectedMac.name,
                        endpoint: selectedMac.endpoint,
                        code: code,
                        deviceName: deviceName,
                        label: label
                    )
                case .manual:
                    guard let port = UInt16(manualPort),
                          let nwPort = NWEndpoint.Port(rawValue: port)
                    else {
                        errorMessage = "Enter a valid port number."
                        isPairing = false
                        return
                    }
                    let endpoint = NWEndpoint.hostPort(
                        host: NWEndpoint.Host(manualHost),
                        port: nwPort
                    )
                    mac = try await client.pair(
                        macName: nil,
                        endpoint: endpoint,
                        code: code,
                        deviceName: deviceName,
                        label: label
                    )
                }
                isPairing = false
                onPaired(mac)
            } catch RemoteClientError.cancelled {
                isPairing = false
            } catch RemoteClientError.timedOut {
                isPairing = false
                errorMessage = "Could not reach the Mac in 30 seconds. "
                    + "Check the address and port."
            } catch RemoteClientError.connectionClosed {
                isPairing = false
                errorMessage = "Could not connect. "
                    + "Check the address and port."
            } catch {
                isPairing = false
                errorMessage = "Could not pair. Check the code and try again."
            }
        }
    }
}
