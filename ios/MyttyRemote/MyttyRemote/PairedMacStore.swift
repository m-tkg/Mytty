import Foundation
import Network
import Security

struct PairedMac: Codable, Equatable, Hashable, Identifiable {
    var deviceID: String
    var deviceSecretBase64: String
    /// Bonjour service instance name, used to reconnect via `.service`
    /// endpoint resolution. Empty when paired via manual host/port entry.
    var macName: String
    var manualHost: String?
    var manualPort: UInt16?
    var displayName: String

    var id: String { deviceID }

    var deviceSecret: Data {
        Data(base64Encoded: deviceSecretBase64) ?? Data()
    }

    var subtitle: String {
        if !macName.isEmpty { return macName }
        if let manualHost, let manualPort { return "\(manualHost):\(manualPort)" }
        return ""
    }

    func reconnectEndpoint() -> NWEndpoint? {
        if !macName.isEmpty {
            return .service(
                name: macName,
                type: "_mytty._tcp",
                domain: "local",
                interface: nil
            )
        }
        if let manualHost, let manualPort,
           let port = NWEndpoint.Port(rawValue: manualPort) {
            return .hostPort(
                host: NWEndpoint.Host(manualHost),
                port: port
            )
        }
        return nil
    }
}

/// Persists every paired Mac's credentials (and enough addressing info to
/// reconnect) in the Keychain as a single JSON array, mirroring the
/// Mac-side `RemotePairedDeviceStore`'s multi-device design.
enum PairedMacStore {
    private static let service = "dev.mytty.remote.pairing"
    private static let account = "paired-macs"

    static func loadAll() -> [PairedMac] {
        if let macs = read(query: baseQuery()) { return macs }
        // Devices paired before the extension existed stored their
        // secrets in the app's own group. Move them across rather than
        // making the user pair every Mac again.
        guard let legacy = read(query: legacyQuery()) else { return [] }
        saveAll(legacy)
        return legacy
    }

    private static func read(query: [String: Any]) -> [PairedMac]? {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result)
                == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode([PairedMac].self, from: data)
    }

    @discardableResult
    static func add(_ mac: PairedMac) -> [PairedMac] {
        var all = loadAll()
        all.removeAll { $0.deviceID == mac.deviceID }
        all.append(mac)
        saveAll(all)
        return all
    }

    @discardableResult
    static func remove(id: String) -> [PairedMac] {
        var all = loadAll()
        all.removeAll { $0.deviceID == id }
        saveAll(all)
        return all
    }

    /// Overwrites the whole list, e.g. after in-place edits (label
    /// renames) to entries already loaded into memory.
    static func replaceAll(_ macs: [PairedMac]) {
        saveAll(macs)
    }

    private static func saveAll(_ macs: [PairedMac]) {
        guard let data = try? JSONEncoder().encode(macs) else { return }
        SecItemDelete(baseQuery() as CFDictionary)
        SecItemDelete(legacyQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    /// The pre-extension query, with no access group, kept only so
    /// `loadAll` can find and migrate what it wrote.
    private static func legacyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// The Keychain group the app shares with its notification service
    /// extension, which needs the pairing secrets to decrypt Attention
    /// pushes. Xcode expands `$(AppIdentifierPrefix)` into both targets'
    /// Info.plist at build time, so neither has to hardcode a team ID.
    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "MyTTYKeychainAccessGroup")
            as? String
    }

    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
