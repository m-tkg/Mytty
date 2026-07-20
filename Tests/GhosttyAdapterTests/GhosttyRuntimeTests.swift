import Foundation
import Testing

@testable import GhosttyAdapter

@Suite("Ghostty runtime")
struct GhosttyRuntimeTests {
    @Test("creates an application runtime from terminal configuration")
    @MainActor
    func createsRuntime() throws {
        try GhosttyLibrary.initializeCurrentProcess()
        let file = try temporaryConfiguration()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let configuration = try GhosttyConfiguration(file: file)

        let runtime = try GhosttyRuntime(configuration: configuration)

        #expect(runtime.isRunning)

        try "font-size = 16\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        let updated = try GhosttyConfiguration(file: file)
        runtime.updateConfiguration(updated)

        #expect(runtime.isRunning)
    }

    private func temporaryConfiguration() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("terminal.conf")
        try "font-size = 13\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        return file
    }
}
