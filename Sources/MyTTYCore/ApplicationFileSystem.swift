import Foundation

public struct ApplicationFileSystem {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func prepare(_ paths: ApplicationPaths) throws {
        for directory in [
            paths.configurationDirectory,
            paths.applicationSupportDirectory,
            paths.logDirectory,
            paths.controlSocket.deletingLastPathComponent(),
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }

        for file in [
            paths.appConfiguration,
            paths.terminalConfiguration,
            paths.agentConfiguration,
        ] {
            if !fileManager.fileExists(atPath: file.path) {
                guard fileManager.createFile(
                    atPath: file.path,
                    contents: Data(),
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: file.path
            )
        }
    }
}
