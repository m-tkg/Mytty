import Foundation

struct RemotePairedDevice: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let secretBase64: String
    let pairedAt: Date
    /// Relay registration reported by the device via `registerPushRelay`.
    /// Absent for devices paired before push existed and for devices whose
    /// user declined the notification prompt; a nil `pushRelayID` simply
    /// means "no Attention pushes for this device". The APNs device token
    /// is deliberately not here — the phone registers it with the relay
    /// directly, so the Mac never holds it.
    var pushRelayID: String? = nil
    var pushRelaySecretBase64: String? = nil
}

enum RemotePairedDeviceStoreError: Error, Equatable {
    case deviceNotFound(String)
}

/// Persists paired iOS devices at `~/Library/Application Support/mytty/remote-devices.json`
/// with owner-only permissions, mirroring the atomic-write pattern used by
/// `AgentIntegrationInstaller` for other user-owned configuration files.
final class RemotePairedDeviceStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [RemotePairedDevice] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([RemotePairedDevice].self, from: data)
    }

    @discardableResult
    func add(_ device: RemotePairedDevice) throws -> [RemotePairedDevice] {
        var devices = try load()
        devices.removeAll { $0.id == device.id }
        devices.append(device)
        try write(devices)
        return devices
    }

    @discardableResult
    func remove(id: String) throws -> [RemotePairedDevice] {
        var devices = try load()
        guard devices.contains(where: { $0.id == id }) else {
            throw RemotePairedDeviceStoreError.deviceNotFound(id)
        }
        devices.removeAll { $0.id == id }
        try write(devices)
        return devices
    }

    @discardableResult
    func rename(id: String, name: String) throws -> [RemotePairedDevice] {
        var devices = try load()
        guard let index = devices.firstIndex(where: { $0.id == id }) else {
            throw RemotePairedDeviceStoreError.deviceNotFound(id)
        }
        devices[index].name = name
        try write(devices)
        return devices
    }

    /// Records (or, with a nil id, clears) the device's relay
    /// registration. Devices re-send this on every connection because iOS
    /// can hand the app a fresh APNs token at any launch, so this is a
    /// plain overwrite rather than a merge.
    @discardableResult
    func updatePushRegistration(
        id: String,
        pushRelayID: String?,
        relaySecretBase64: String?
    ) throws -> [RemotePairedDevice] {
        var devices = try load()
        guard let index = devices.firstIndex(where: { $0.id == id }) else {
            throw RemotePairedDeviceStoreError.deviceNotFound(id)
        }
        guard devices[index].pushRelayID != pushRelayID
            || devices[index].pushRelaySecretBase64 != relaySecretBase64
        else { return devices }
        devices[index].pushRelayID = pushRelayID
        devices[index].pushRelaySecretBase64 = relaySecretBase64
        try write(devices)
        return devices
    }

    func device(id: String) throws -> RemotePairedDevice? {
        try load().first { $0.id == id }
    }

    private func write(_ devices: [RemotePairedDevice]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(devices)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
