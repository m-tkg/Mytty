import Foundation
import Network

/// A Mac this client has paired with, plus enough addressing information to
/// reconnect to it later. Shared by every client: the iOS remote keeps
/// these in the Keychain (`PairedMacStore`), while a Mac acting as a client
/// keeps them in a file (`RemoteHostStore`), because each platform already
/// had a store of that shape for its own pairing records.
public struct PairedMac: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var deviceID: String
    public var deviceSecretBase64: String
    /// Bonjour service instance name, used to reconnect via `.service`
    /// endpoint resolution. Empty when paired via manual host/port entry.
    public var macName: String
    public var manualHost: String?
    public var manualPort: UInt16?
    public var displayName: String

    public init(
        deviceID: String,
        deviceSecretBase64: String,
        macName: String,
        manualHost: String? = nil,
        manualPort: UInt16? = nil,
        displayName: String
    ) {
        self.deviceID = deviceID
        self.deviceSecretBase64 = deviceSecretBase64
        self.macName = macName
        self.manualHost = manualHost
        self.manualPort = manualPort
        self.displayName = displayName
    }

    public var id: String { deviceID }

    public var deviceSecret: Data {
        Data(base64Encoded: deviceSecretBase64) ?? Data()
    }

    public var subtitle: String {
        if !macName.isEmpty { return macName }
        if let manualHost, let manualPort { return "\(manualHost):\(manualPort)" }
        return ""
    }

    public func reconnectEndpoint() -> NWEndpoint? {
        if !macName.isEmpty {
            return .service(
                name: macName,
                type: RemoteBonjour.serviceType,
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

public enum RemoteBonjour {
    /// The Bonjour type a Mytty Mac advertises its remote-access server on,
    /// and the one every client browses for.
    public static let serviceType = "_mytty._tcp"
}
