import Combine
import Foundation
import Network

public struct DiscoveredMac: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(id: String, name: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }

    public static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
        lhs.id == rhs.id
    }
}

/// Browses Bonjour for Macs advertising a Mytty remote-access server, so a
/// client can offer them by name instead of asking for a host and port.
@MainActor
public final class MacDiscovery: ObservableObject {
    @Published public private(set) var discovered: [DiscoveredMac] = []

    private var browser: NWBrowser?

    public init() {}

    public func start() {
        stop()
        let browser = NWBrowser(
            for: .bonjour(type: RemoteBonjour.serviceType, domain: nil),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let discovered: [DiscoveredMac] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint
                else { return nil }
                return DiscoveredMac(
                    id: name,
                    name: name,
                    endpoint: result.endpoint
                )
            }
            Task { @MainActor [weak self] in
                self?.discovered = discovered
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        discovered = []
    }
}
