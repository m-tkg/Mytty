import Foundation
import GhosttyKit

public enum GhosttyConfigurationError: Error, Equatable, Sendable {
    case allocationFailed
}

public final class GhosttyConfiguration {
    let native: ghostty_config_t

    public let diagnostics: [String]

    public init(file: URL) throws {
        guard let native = ghostty_config_new() else {
            throw GhosttyConfigurationError.allocationFailed
        }

        self.native = native

        file.path.withCString { path in
            ghostty_config_load_file(native, path)
        }
        ghostty_config_load_recursive_files(native)
        ghostty_config_finalize(native)

        diagnostics = Self.readDiagnostics(from: native)
    }

    deinit {
        ghostty_config_free(native)
    }

    private static func readDiagnostics(
        from native: ghostty_config_t
    ) -> [String] {
        (0..<ghostty_config_diagnostics_count(native)).map { index in
            let diagnostic = ghostty_config_get_diagnostic(native, index)
            return String(cString: diagnostic.message)
        }
    }
}
