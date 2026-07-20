import Foundation
import MyTTYCore

enum ApplicationIdentity {
    private static let releaseBundleIdentifier = "com.m-tkg.mytty"
    private static let developmentBundleIdentifier = "com.m-tkg.mytty.dev"

    static let isDevelopmentBuild: Bool = {
        switch Bundle.main.bundleIdentifier {
        case developmentBundleIdentifier:
            true
        case releaseBundleIdentifier:
            false
        default:
            #if DEBUG
            true
            #else
            false
            #endif
        }
    }()

    static let displayName = isDevelopmentBuild ? "Mytty Dev" : "Mytty"
    static let bundleIdentifier = isDevelopmentBuild
        ? developmentBundleIdentifier
        : releaseBundleIdentifier
    static let pathProfile: ApplicationPathProfile = isDevelopmentBuild
        ? .development
        : .release
    static let dockBadge: String? = isDevelopmentBuild ? "DEV" : nil
    static let supportsSelfUpdate = !isDevelopmentBuild
    static let developerTeamIdentifier = "G72M73C546"

    static var version: ApplicationVersion {
        let value = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return ApplicationVersion(value ?? "0.1.0")!
    }
}
