import Foundation

/// Copies the release build's configuration files into another profile's
/// configuration directory. Development builds use this to pick up the
/// settings of an installed Mytty release without hand-copying files.
public struct ReleaseSettingsImporter {
    public enum ImportError: Error, Equatable, Sendable {
        /// The source has no configuration files to import.
        case sourceNotFound
        /// A source preferences file exists but does not parse; nothing
        /// is imported so the destination is never left half-updated.
        case invalidSourceConfiguration
    }

    public struct Summary: Equatable, Sendable {
        public let importedFileNames: [String]
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func importSettings(
        from source: ApplicationPaths,
        to destination: ApplicationPaths
    ) throws -> Summary {
        let files: [(source: URL, destination: URL)] = [
            (source.appConfiguration, destination.appConfiguration),
            (source.terminalConfiguration, destination.terminalConfiguration),
            (source.agentConfiguration, destination.agentConfiguration),
        ]
        let present = files.filter {
            fileManager.fileExists(atPath: $0.source.path)
        }
        guard !present.isEmpty else {
            throw ImportError.sourceNotFound
        }

        // Validate before touching the destination so a malformed release
        // configuration never destroys the development settings.
        do {
            if fileManager.fileExists(atPath: source.appConfiguration.path) {
                _ = try ApplicationPreferencesStore(fileManager: fileManager)
                    .load(from: source.appConfiguration)
            }
            if fileManager.fileExists(
                atPath: source.terminalConfiguration.path
            ) {
                _ = try TerminalPreferencesStore(fileManager: fileManager)
                    .load(from: source.terminalConfiguration)
            }
        } catch {
            throw ImportError.invalidSourceConfiguration
        }

        try fileManager.createDirectory(
            at: destination.configurationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var importedFileNames: [String] = []
        for file in present {
            let data = try Data(contentsOf: file.source)
            try data.write(to: file.destination, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: file.destination.path
            )
            importedFileNames.append(file.destination.lastPathComponent)
        }
        return Summary(importedFileNames: importedFileNames)
    }
}
