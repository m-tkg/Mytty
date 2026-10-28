import Foundation
import GhosttyKit
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

    @Test("clipboard confirmation selects text by MIME and respects byte length")
    func confirmationText() {
        let bytes: [CChar] = [65, 0, 66, 67]
        bytes.withUnsafeBufferPointer { buffer in
            "text/plain".withCString { mime in
                var content = ghostty_clipboard_content_s(mime: mime, data: buffer.baseAddress, len: 3)
                withUnsafePointer(to: &content) { pointer in
                    var confirm = ghostty_clipboard_confirm_s()
                    confirm.contents = pointer
                    confirm.contents_len = 0
                    #expect(GhosttyRuntime.confirmationText(confirm) == nil)
                    confirm.contents_len = 1
                    #expect(GhosttyRuntime.confirmationText(confirm) == "A\0B")
                }
            }
            "image/png".withCString { mime in
                var content = ghostty_clipboard_content_s(mime: mime, data: buffer.baseAddress, len: 3)
                withUnsafePointer(to: &content) { pointer in
                    var confirm = ghostty_clipboard_confirm_s()
                    confirm.contents = pointer
                    confirm.contents_len = 1
                    #expect(GhosttyRuntime.confirmationText(confirm) == nil)
                }
            }
        }
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
