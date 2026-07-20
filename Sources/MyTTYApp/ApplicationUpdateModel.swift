import Combine
import Foundation

enum ApplicationUpdateFailure: Equatable, Sendable {
    case check
    case installation
}

enum ApplicationUpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate(ApplicationVersion)
    case available(ApplicationUpdateRelease)
    case installing(ApplicationUpdateRelease)
    case installed(ApplicationVersion)
    case failed(ApplicationUpdateFailure)
}

@MainActor
final class ApplicationUpdateModel: ObservableObject {
    @Published private(set) var phase: ApplicationUpdatePhase = .idle

    let currentVersion: ApplicationVersion

    var canCheck: Bool {
        switch phase {
        case .checking, .installing:
            false
        default:
            true
        }
    }

    var canUpdate: Bool {
        availableRelease != nil && canCheck
    }

    private let checker: any ApplicationUpdateChecking
    private let installer: any ApplicationUpdateInstalling
    private let confirmsInstallation: @MainActor () -> Bool
    private let onInstalled: @MainActor () -> Void
    private var availableRelease: ApplicationUpdateRelease?

    init(
        currentVersion: ApplicationVersion,
        checker: any ApplicationUpdateChecking,
        installer: any ApplicationUpdateInstalling,
        confirmsInstallation: @escaping @MainActor () -> Bool,
        onInstalled: @escaping @MainActor () -> Void
    ) {
        self.currentVersion = currentVersion
        self.checker = checker
        self.installer = installer
        self.confirmsInstallation = confirmsInstallation
        self.onInstalled = onInstalled
    }

    func checkForUpdates(includePrereleases: Bool = false) async {
        guard canCheck else { return }
        availableRelease = nil
        phase = .checking
        do {
            let release = try await checker.latestRelease(
                includePrereleases: includePrereleases
            )
            guard release.version > currentVersion else {
                phase = .upToDate(currentVersion)
                return
            }
            availableRelease = release
            phase = .available(release)
        } catch {
            phase = .failed(.check)
        }
    }

    func installAvailableUpdate() async {
        guard let release = availableRelease,
              canUpdate,
              confirmsInstallation()
        else { return }
        phase = .installing(release)
        do {
            try await installer.install(release)
            availableRelease = nil
            phase = .installed(release.version)
            onInstalled()
        } catch {
            phase = .failed(.installation)
        }
    }
}

enum ApplicationUpdateCheckTrigger: Equatable, Sendable {
    case launch
    case about

    var offersInstallation: Bool {
        self == .launch
    }
}

@MainActor
struct ApplicationUpdateAutomation {
    let model: ApplicationUpdateModel

    func check(trigger: ApplicationUpdateCheckTrigger) async {
        await model.checkForUpdates()
        guard trigger.offersInstallation,
              case .available = model.phase
        else { return }
        await model.installAvailableUpdate()
    }
}
