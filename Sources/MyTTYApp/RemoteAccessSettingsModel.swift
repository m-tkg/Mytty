import Foundation
import MyTTYRemoteKit

@MainActor
final class RemoteAccessSettingsModel: ObservableObject {
    @Published private(set) var pairedDevices: [RemotePairedDevice] = []
    @Published private(set) var activeCode: RemotePairingCode?
    @Published private(set) var listeningPort: UInt16?

    private let server: RemoteAccessServer

    init(server: RemoteAccessServer) {
        self.server = server
        server.onDeviceListChanged = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        pairedDevices = server.pairedDevices()
        // An expired code can no longer pair anything, so surface the
        // "generate" button again instead of a dead code.
        if let code = server.pairingCoordinator.activeCode, code.isExpired() {
            server.pairingCoordinator.cancelPairing()
        }
        activeCode = server.pairingCoordinator.activeCode
        listeningPort = server.listeningPort
    }

    func generateCode() {
        activeCode = server.pairingCoordinator.beginPairing()
    }

    func cancelPairing() {
        server.pairingCoordinator.cancelPairing()
        activeCode = nil
    }

    func removeDevice(_ device: RemotePairedDevice) {
        _ = server.unpair(deviceID: device.id)
        refresh()
    }

    func renameDevice(_ device: RemotePairedDevice, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        _ = server.renamePairedDevice(deviceID: device.id, name: trimmedName)
        refresh()
    }
}
