import Foundation
import MyTTYRemoteKit

enum RemoteHostStoreError: Error, Equatable {
    case hostNotFound(String)
}

/// Persists the Macs this Mac has paired with *as a client*, at
/// `~/Library/Application Support/mytty/remote-hosts.json` with owner-only
/// permissions.
///
/// The iOS remote keeps the same records in the Keychain, because its
/// notification extension has to read them while the phone is locked. On
/// the Mac there is no extension and no such constraint, so this follows
/// `RemotePairedDeviceStore`'s atomic-file pattern instead — which also
/// keeps a debug build's records under its own isolated support directory.
final class RemoteHostStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [PairedMac] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([PairedMac].self, from: data)
    }

    @discardableResult
    func add(_ host: PairedMac) throws -> [PairedMac] {
        var hosts = try load()
        hosts.removeAll { $0.deviceID == host.deviceID }
        hosts.append(host)
        try write(hosts)
        return hosts
    }

    @discardableResult
    func remove(id: String) throws -> [PairedMac] {
        var hosts = try load()
        guard hosts.contains(where: { $0.deviceID == id }) else {
            throw RemoteHostStoreError.hostNotFound(id)
        }
        hosts.removeAll { $0.deviceID == id }
        try write(hosts)
        return hosts
    }

    @discardableResult
    func rename(id: String, name: String) throws -> [PairedMac] {
        var hosts = try load()
        guard let index = hosts.firstIndex(where: { $0.deviceID == id }) else {
            throw RemoteHostStoreError.hostNotFound(id)
        }
        hosts[index].displayName = name
        try write(hosts)
        return hosts
    }

    func host(id: String) throws -> PairedMac? {
        try load().first { $0.deviceID == id }
    }

    private func write(_ hosts: [PairedMac]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(hosts)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
