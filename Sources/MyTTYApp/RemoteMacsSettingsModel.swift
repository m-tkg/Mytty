import AppKit
import Foundation
import MyTTYRemoteKit
import Network

/// Drives the client half of remote access in Settings: the Macs this Mac
/// can open remote panes onto, and the pairing flow that adds one.
///
/// Pairing is driven by a link rather than a scanned QR code. The host
/// already encodes its pairing token as a `mytty://pair?...` URL for the
/// phone's camera; on a Mac there is no camera in the loop, so the user
/// copies that link on the host and pastes it here.
@MainActor
final class RemoteMacsSettingsModel: ObservableObject {
    enum PairingState: Equatable {
        case idle
        case pairing
        case failed(String)
    }

    @Published private(set) var hosts: [PairedMac] = []
    @Published private(set) var pairingState: PairingState = .idle
    @Published private(set) var discovered: [DiscoveredMac] = []

    private let connections: RemotePaneConnectionCoordinator
    private let discovery = MacDiscovery()
    private let client = RemoteClient()
    private var discoveryObserver: NSObjectProtocol?
    private var pairingTask: Task<Void, Never>?

    init(connections: RemotePaneConnectionCoordinator) {
        self.connections = connections
        refresh()
    }

    func refresh() {
        hosts = connections.hosts()
    }

    func startDiscovery() {
        discovery.start()
        // `MacDiscovery` publishes through Combine; mirroring it here keeps
        // the view observing a single object.
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await macs in self.discovery.$discovered.values {
                self.discovered = macs
            }
        }
    }

    func stopDiscovery() {
        discovery.stop()
        discovered = []
    }

    /// Pairs with a Mac using a link copied from its Settings. `endpoint`
    /// picks where to connect: a Bonjour service found by discovery, or a
    /// host and port typed by hand.
    func pair(
        link: String,
        endpoint: PairingEndpoint,
        label: String
    ) {
        guard let payload = RemotePairingPayload.parse(link) else {
            pairingState = .failed(RemotePairingFailure.invalidLink.rawValue)
            return
        }
        guard let resolved = endpoint.networkEndpoint else {
            pairingState = .failed(RemotePairingFailure.noAddress.rawValue)
            return
        }
        pairingState = .pairing
        pairingTask?.cancel()
        pairingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let mac = try await self.client.pair(
                    macName: endpoint.bonjourName,
                    endpoint: resolved,
                    token: payload.token,
                    deviceName: Host.current().localizedName ?? "Mac",
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                self.connections.addHost(mac)
                self.refresh()
                self.pairingState = .idle
            } catch is CancellationError {
                self.pairingState = .idle
            } catch {
                self.pairingState = .failed(Self.message(for: error))
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        client.cancelPairing()
        pairingState = .idle
    }

    func remove(_ host: PairedMac) {
        hosts = connections.removeHost(id: host.deviceID)
    }

    func rename(_ host: PairedMac, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hosts = connections.renameHost(id: host.deviceID, name: trimmed)
    }

    /// Where to reach the Mac being paired with.
    enum PairingEndpoint: Equatable {
        case bonjour(DiscoveredMac)
        case address(host: String, port: UInt16)

        var bonjourName: String? {
            if case let .bonjour(mac) = self { return mac.name }
            return nil
        }

        var networkEndpoint: NWEndpoint? {
            switch self {
            case let .bonjour(mac):
                return mac.endpoint
            case let .address(host, port):
                guard !host.isEmpty, let port = NWEndpoint.Port(rawValue: port)
                else { return nil }
                return .hostPort(host: NWEndpoint.Host(host), port: port)
            }
        }
    }

    /// Failure reasons the view turns into localized text. Kept as a plain
    /// enum so the model stays free of the localizer.
    enum RemotePairingFailure: String {
        case invalidLink
        case noAddress
        case timedOut
        case refused
    }

    private static func message(for error: Error) -> String {
        switch error {
        case RemoteClientError.timedOut:
            RemotePairingFailure.timedOut.rawValue
        case RemoteClientError.connectionClosed,
             RemoteClientError.protocolError:
            RemotePairingFailure.refused.rawValue
        case RemoteClientError.noEndpoint:
            RemotePairingFailure.noAddress.rawValue
        default:
            RemotePairingFailure.refused.rawValue
        }
    }
}
