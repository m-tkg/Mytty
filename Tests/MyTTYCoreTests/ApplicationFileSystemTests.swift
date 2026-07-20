import Foundation
import Testing

@testable import MyTTYCore

@Suite("Application file system")
struct ApplicationFileSystemTests {
    @Test("creates required configuration and runtime locations")
    func createsRequiredLocations() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationPaths(
            homeDirectory: root,
            temporaryDirectory: root.appendingPathComponent("tmp")
        )

        try ApplicationFileSystem().prepare(paths)

        #expect(FileManager.default.fileExists(atPath: paths.configurationDirectory.path))
        #expect(FileManager.default.fileExists(atPath: paths.appConfiguration.path))
        #expect(FileManager.default.fileExists(atPath: paths.terminalConfiguration.path))
        #expect(FileManager.default.fileExists(atPath: paths.agentConfiguration.path))
        #expect(FileManager.default.fileExists(atPath: paths.applicationSupportDirectory.path))
        #expect(FileManager.default.fileExists(atPath: paths.logDirectory.path))
    }

    @Test("preserves existing user configuration")
    func preservesExistingConfiguration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationPaths(
            homeDirectory: root,
            temporaryDirectory: root.appendingPathComponent("tmp")
        )
        try FileManager.default.createDirectory(
            at: paths.configurationDirectory,
            withIntermediateDirectories: true
        )
        try "font-size = 16\n".write(
            to: paths.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )

        try ApplicationFileSystem().prepare(paths)

        let contents = try String(
            contentsOf: paths.terminalConfiguration,
            encoding: .utf8
        )
        #expect(contents == "font-size = 16\n")
    }

    @Test("restricts local configuration and runtime permissions")
    func restrictsLocalPermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationPaths(
            homeDirectory: root,
            temporaryDirectory: root.appendingPathComponent("tmp")
        )
        let temporaryDirectory = paths.controlSocket
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.createDirectory(
            at: paths.configurationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try Data("existing = true\n".utf8).write(
            to: paths.appConfiguration
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: paths.appConfiguration.path
        )

        try ApplicationFileSystem().prepare(paths)

        for directory in [
            paths.configurationDirectory,
            paths.applicationSupportDirectory,
            paths.logDirectory,
            paths.controlSocket.deletingLastPathComponent(),
        ] {
            #expect(try permissions(at: directory) == 0o700)
        }
        #expect(try permissions(at: temporaryDirectory) == 0o755)
        for file in [
            paths.appConfiguration,
            paths.terminalConfiguration,
            paths.agentConfiguration,
        ] {
            #expect(try permissions(at: file) == 0o600)
        }
        #expect(
            try String(contentsOf: paths.appConfiguration, encoding: .utf8)
                == "existing = true\n"
        )
    }

    private func permissions(at url: URL) throws -> Int {
        try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[
                .posixPermissions
            ] as? Int
        )
    }
}
