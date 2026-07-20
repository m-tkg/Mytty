import Foundation
import Network

struct DiscoveredMac: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint

    static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class MacDiscovery: ObservableObject {
    @Published private(set) var discovered: [DiscoveredMac] = []

    private var browser: NWBrowser?

    func start() {
        stop()
        let browser = NWBrowser(
            for: .bonjour(type: "_mytty._tcp", domain: nil),
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

    func stop() {
        browser?.cancel()
        browser = nil
        discovered = []
    }
}
