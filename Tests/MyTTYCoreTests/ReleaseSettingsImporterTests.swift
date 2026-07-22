import Foundation
import Testing

@testable import MyTTYCore

@Suite("Release settings importer")
struct ReleaseSettingsImporterTests {
    @Test("copies release configuration files into the destination")
    func importsAllConfigurationFiles() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try harness.writeSource(
            application: "tab-position = \"bottom\"\n",
            terminal: "font-size = 18\n",
            agents: "# agents\n"
        )
        try harness.writeDestination(
            application: "tab-position = \"top\"\n",
            terminal: "font-size = 11\n",
            agents: ""
        )

        let summary = try ReleaseSettingsImporter().importSettings(
            from: harness.source,
            to: harness.destination
        )

        #expect(
            summary.importedFileNames
                == ["config.toml", "terminal.conf", "agents.toml"]
        )
        #expect(
            try harness.destinationContents(of: \.appConfiguration)
                == "tab-position = \"bottom\"\n"
        )
        #expect(
            try harness.destinationContents(of: \.terminalConfiguration)
                == "font-size = 18\n"
        )
        #expect(
            try harness.destinationContents(of: \.agentConfiguration)
                == "# agents\n"
        )
        let permissions = try FileManager.default.attributesOfItem(
            atPath: harness.destination.appConfiguration.path
        )[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test("imports only the files present in the source")
    func importsPartialSource() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try harness.writeSource(
            application: "tab-position = \"bottom\"\n",
            terminal: nil,
            agents: nil
        )
        try harness.writeDestination(
            application: "",
            terminal: "font-size = 11\n",
            agents: ""
        )

        let summary = try ReleaseSettingsImporter().importSettings(
            from: harness.source,
            to: harness.destination
        )

        #expect(summary.importedFileNames == ["config.toml"])
        #expect(
            try harness.destinationContents(of: \.terminalConfiguration)
                == "font-size = 11\n"
        )
    }

    @Test("creates the destination directory when it does not exist")
    func createsDestinationDirectory() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try harness.writeSource(
            application: "tab-position = \"bottom\"\n",
            terminal: nil,
            agents: nil
        )

        let summary = try ReleaseSettingsImporter().importSettings(
            from: harness.source,
            to: harness.destination
        )

        #expect(summary.importedFileNames == ["config.toml"])
        #expect(
            try harness.destinationContents(of: \.appConfiguration)
                == "tab-position = \"bottom\"\n"
        )
    }

    @Test("reports a missing source instead of importing nothing")
    func missingSource() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try harness.writeDestination(
            application: "",
            terminal: "",
            agents: ""
        )

        #expect(
            throws: ReleaseSettingsImporter.ImportError.sourceNotFound
        ) {
            try ReleaseSettingsImporter().importSettings(
                from: harness.source,
                to: harness.destination
            )
        }
    }

    @Test("rejects a source whose preferences do not parse")
    func invalidSource() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try harness.writeSource(
            application: "tab-position = \"sideways\"\n",
            terminal: "font-size = 18\n",
            agents: nil
        )
        try harness.writeDestination(
            application: "tab-position = \"top\"\n",
            terminal: "font-size = 11\n",
            agents: ""
        )

        #expect(
            throws: ReleaseSettingsImporter.ImportError
                .invalidSourceConfiguration
        ) {
            try ReleaseSettingsImporter().importSettings(
                from: harness.source,
                to: harness.destination
            )
        }
        #expect(
            try harness.destinationContents(of: \.appConfiguration)
                == "tab-position = \"top\"\n"
        )
        #expect(
            try harness.destinationContents(of: \.terminalConfiguration)
                == "font-size = 11\n"
        )
    }
}

private struct Harness {
    let root: URL
    let source: ApplicationPaths
    let destination: ApplicationPaths

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        source = ApplicationPaths(
            homeDirectory: root,
            temporaryDirectory: temporary,
            profile: .release
        )
        destination = ApplicationPaths(
            homeDirectory: root,
            temporaryDirectory: temporary,
            profile: .development
        )
    }

    func writeSource(
        application: String?,
        terminal: String?,
        agents: String?
    ) throws {
        try write(
            application: application,
            terminal: terminal,
            agents: agents,
            to: source
        )
    }

    func writeDestination(
        application: String?,
        terminal: String?,
        agents: String?
    ) throws {
        try write(
            application: application,
            terminal: terminal,
            agents: agents,
            to: destination
        )
    }

    func destinationContents(
        of file: KeyPath<ApplicationPaths, URL>
    ) throws -> String {
        try String(
            contentsOf: destination[keyPath: file],
            encoding: .utf8
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(
        application: String?,
        terminal: String?,
        agents: String?,
        to paths: ApplicationPaths
    ) throws {
        try FileManager.default.createDirectory(
            at: paths.configurationDirectory,
            withIntermediateDirectories: true
        )
        let files: [(String?, URL)] = [
            (application, paths.appConfiguration),
            (terminal, paths.terminalConfiguration),
            (agents, paths.agentConfiguration),
        ]
        for (contents, url) in files {
            guard let contents else { continue }
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
