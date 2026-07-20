import Foundation
import Testing

@testable import GhosttyAdapter

@Suite("Ghostty configuration")
struct GhosttyConfigurationTests {
    @Test("loads a valid terminal configuration")
    func validConfiguration() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration(contents: "font-size = 13\n")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let configuration = try GhosttyConfiguration(file: file)

        #expect(configuration.diagnostics.isEmpty)
    }

    @Test("reports invalid terminal configuration")
    func invalidConfiguration() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration(contents: "font-size = invalid\n")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let configuration = try GhosttyConfiguration(file: file)

        #expect(!configuration.diagnostics.isEmpty)
    }

    private func temporaryConfiguration(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("terminal.conf")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
