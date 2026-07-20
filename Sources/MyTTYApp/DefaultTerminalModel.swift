import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
protocol DefaultTerminalRegistering: AnyObject {
    func defaultApplicationURL() -> URL?
    func setDefaultApplication(at applicationURL: URL) async throws
}

@MainActor
final class WorkspaceDefaultTerminalRegistrar: DefaultTerminalRegistering {
    func defaultApplicationURL() -> URL? {
        LSCopyDefaultApplicationURLForContentType(
            UTType.unixExecutable.identifier as CFString,
            .all,
            nil
        )?.takeRetainedValue() as? URL
    }

    func setDefaultApplication(at applicationURL: URL) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.setDefaultApplication(
                at: applicationURL,
                toOpen: .unixExecutable
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

enum DefaultTerminalFailure: Equatable {
    case registration
}

@MainActor
final class DefaultTerminalModel: ObservableObject {
    @Published private(set) var isDefault = false
    @Published private(set) var isUpdating = false
    @Published private(set) var failure: DefaultTerminalFailure?

    private let applicationURL: URL
    private let registrar: any DefaultTerminalRegistering

    init(
        applicationURL: URL,
        registrar: any DefaultTerminalRegistering
    ) {
        self.applicationURL = applicationURL
        self.registrar = registrar
    }

    func refresh() {
        isDefault = registrar.defaultApplicationURL().map(canonicalURL)
            == canonicalURL(applicationURL)
        failure = nil
    }

    func makeDefault() async {
        guard !isUpdating else { return }
        isUpdating = true
        failure = nil
        do {
            try await registrar.setDefaultApplication(at: applicationURL)
            isDefault = registrar.defaultApplicationURL().map(canonicalURL)
                == canonicalURL(applicationURL)
            if !isDefault {
                failure = .registration
            }
        } catch {
            isDefault = false
            failure = .registration
        }
        isUpdating = false
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
