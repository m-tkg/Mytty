import Foundation
import Testing

@testable import MyTTYApp

@Suite("Command line tool install")
struct CommandLineToolInstallModelTests {
    @Test("creates the symlink and reports installed")
    @MainActor
    func installsFreshLink() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()

        model.install()

        #expect(model.isInstalled)
        #expect(!model.isUpdating)
        #expect(model.failure == nil)
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: fixture.linkURL.path
            ) == fixture.executableURL.path
        )
    }

    @Test("refresh recognizes a link this build already installed")
    @MainActor
    func refreshRecognizesExistingLink() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(
            at: fixture.binDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.linkURL,
            withDestinationURL: fixture.executableURL
        )
        let model = fixture.makeModel()

        model.refresh()

        #expect(model.isInstalled)
        #expect(model.failure == nil)
    }

    @Test("install is idempotent once the link already points here")
    @MainActor
    func installIsIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()

        model.install()
        model.install()

        #expect(model.isInstalled)
        #expect(model.failure == nil)
    }

    @Test("refuses to overwrite a real file at the link path")
    @MainActor
    func refusesToOverwriteRealFile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(
            at: fixture.binDirectory,
            withIntermediateDirectories: true
        )
        try Data("not mytty-ctl".utf8).write(to: fixture.linkURL)
        let model = fixture.makeModel()

        model.install()

        #expect(!model.isInstalled)
        #expect(model.failure == .conflict)
        // The pre-existing file must survive untouched.
        #expect(
            try String(contentsOf: fixture.linkURL, encoding: .utf8)
                == "not mytty-ctl"
        )
    }

    @Test("refuses to repoint a symlink that targets something else")
    @MainActor
    func refusesToRepointForeignSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(
            at: fixture.binDirectory,
            withIntermediateDirectories: true
        )
        let other = fixture.directory.appendingPathComponent("other-tool")
        try Data().write(to: other)
        try FileManager.default.createSymbolicLink(
            at: fixture.linkURL,
            withDestinationURL: other
        )
        let model = fixture.makeModel()

        model.install()

        #expect(!model.isInstalled)
        #expect(model.failure == .conflict)
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: fixture.linkURL.path
            ) == other.path
        )
    }

    @Test("flags when ~/.local/bin isn't on PATH, once installed")
    @MainActor
    func flagsMissingPathEntry() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let modelWithout = fixture.makeModel(environmentPath: { "/usr/bin:/bin" })
        modelWithout.install()
        #expect(modelWithout.pathHintNeeded)

        let modelWith = fixture.makeModel(environmentPath: {
            "/usr/bin:\(fixture.binDirectory.path):/bin"
        })
        modelWith.install()
        #expect(!modelWith.pathHintNeeded)
    }

    @Test("surfaces a filesystem failure without crashing")
    @MainActor
    func reportsFilesystemFailure() {
        let linker = ThrowingLinker()
        let model = CommandLineToolInstallModel(
            executableURL: URL(fileURLWithPath: "/tmp/does-not-matter"),
            binDirectory: URL(fileURLWithPath: "/tmp/does-not-matter-bin"),
            linkName: "mytty-ctl",
            linker: linker
        )

        model.install()

        #expect(!model.isInstalled)
        #expect(model.failure == .filesystem)
    }
}

@MainActor
private final class Fixture {
    let directory: URL
    let executableURL: URL
    let binDirectory: URL

    var linkURL: URL {
        binDirectory.appendingPathComponent("mytty-ctl", isDirectory: false)
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        executableURL = directory.appendingPathComponent("mytty-ctl-real")
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        binDirectory = directory.appendingPathComponent(
            "local-bin",
            isDirectory: true
        )
    }

    func makeModel(
        environmentPath: @escaping () -> String? = { nil }
    ) -> CommandLineToolInstallModel {
        CommandLineToolInstallModel(
            executableURL: executableURL,
            binDirectory: binDirectory,
            linkName: "mytty-ctl",
            linker: FileManagerCommandLineToolLinker(),
            environmentPath: environmentPath
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ThrowingLinker: CommandLineToolLinking {
    func ensureDirectoryExists(at directory: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }

    func existingLinkDestination(at linkURL: URL) -> URL? { nil }

    func isNonSymlinkItem(at linkURL: URL) -> Bool { false }

    func createSymbolicLink(
        at linkURL: URL,
        pointingTo targetURL: URL
    ) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}
