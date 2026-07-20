import Foundation
import GhosttyKit

public enum GhosttyBuildMode: Equatable, Sendable {
    case debug
    case releaseSafe
    case releaseFast
    case releaseSmall
    case unknown
}

public struct GhosttyBuildInfo: Equatable, Sendable {
    public let version: String
    public let buildMode: GhosttyBuildMode

    public init(version: String, buildMode: GhosttyBuildMode) {
        self.version = version
        self.buildMode = buildMode
    }
}

public enum GhosttyInitializationError: Error, Equatable, Sendable {
    case failed(code: CInt)
}

public enum GhosttyLibrary {
    private static let initialization = InitializationState()

    public static func initializeCurrentProcess(
        resourcesDirectory: URL? = nil
    ) throws {
        try initialization.runOnce {
            if let resourcesDirectory {
                setenv(
                    "GHOSTTY_RESOURCES_DIR",
                    resourcesDirectory.path,
                    1
                )
            }
            let code = ghostty_init(
                UInt(CommandLine.argc),
                CommandLine.unsafeArgv
            )
            guard code == GHOSTTY_SUCCESS else {
                throw GhosttyInitializationError.failed(code: code)
            }
        }
    }

    public static func buildInfo() -> GhosttyBuildInfo {
        let native = ghostty_info()

        return GhosttyBuildInfo(
            version: decodeVersion(native),
            buildMode: decodeBuildMode(native.build_mode)
        )
    }

    private static func decodeVersion(_ info: ghostty_info_s) -> String {
        guard let version = info.version, info.version_len > 0 else {
            return ""
        }

        let bytes = UnsafeRawPointer(version)
            .assumingMemoryBound(to: UInt8.self)
        return String(
            decoding: UnsafeBufferPointer(
                start: bytes,
                count: Int(info.version_len)
            ),
            as: UTF8.self
        )
    }

    private static func decodeBuildMode(
        _ mode: ghostty_build_mode_e
    ) -> GhosttyBuildMode {
        switch mode {
        case GHOSTTY_BUILD_MODE_DEBUG:
            .debug
        case GHOSTTY_BUILD_MODE_RELEASE_SAFE:
            .releaseSafe
        case GHOSTTY_BUILD_MODE_RELEASE_FAST:
            .releaseFast
        case GHOSTTY_BUILD_MODE_RELEASE_SMALL:
            .releaseSmall
        default:
            .unknown
        }
    }
}

private final class InitializationState: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func runOnce(_ initialize: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        if let result {
            return try result.get()
        }

        let result = Result(catching: initialize)
        self.result = result
        return try result.get()
    }
}
