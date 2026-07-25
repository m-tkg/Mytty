import Foundation
import Testing

@testable import MyTTYCore

@Suite("Claude Code model selection")
struct ClaudeCodeModelSelectionTests {
    /// Everything the resolver reads lives under one throwaway root, so the
    /// suite never depends on the developer's own Claude Code settings.
    private struct Fixture {
        let root: URL
        let workingDirectory: URL
        let claudeHome: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            workingDirectory = root
                .appendingPathComponent("project", isDirectory: true)
            claudeHome = root
                .appendingPathComponent(".claude", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workingDirectory.appendingPathComponent(
                    ".claude",
                    isDirectory: true
                ),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: claudeHome,
                withIntermediateDirectories: true
            )
        }

        func writeProjectLocalSettings(_ contents: String) throws {
            try write(
                contents,
                to: workingDirectory
                    .appendingPathComponent(".claude", isDirectory: true)
                    .appendingPathComponent("settings.local.json")
            )
        }

        func writeProjectSettings(_ contents: String) throws {
            try write(
                contents,
                to: workingDirectory
                    .appendingPathComponent(".claude", isDirectory: true)
                    .appendingPathComponent("settings.json")
            )
        }

        func writeUserSettings(_ contents: String) throws {
            try write(
                contents,
                to: claudeHome.appendingPathComponent("settings.json")
            )
        }

        func resolve(arguments: [String] = []) -> String? {
            ClaudeCodeModelSelection.resolve(
                arguments: arguments,
                workingDirectory: workingDirectory,
                claudeHome: claudeHome
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }

        private func write(_ contents: String, to url: URL) throws {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @Test("prefers the launch argument over every settings file")
    func argumentWins() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeProjectLocalSettings(#"{"model":"sonnet"}"#)
        try fixture.writeUserSettings(#"{"model":"haiku"}"#)

        #expect(
            fixture.resolve(arguments: ["--model", "opus[1m]"]) == "opus[1m]"
        )
        #expect(fixture.resolve(arguments: ["--model=opus[1m]"]) == "opus[1m]")
    }

    @Test("takes the last --model when the flag repeats")
    func lastArgumentWins() {
        #expect(
            ClaudeCodeModelSelection.model(
                fromArguments: [
                    "claude", "--model", "sonnet", "--model=opus[1m]",
                ]
            ) == "opus[1m]"
        )
    }

    @Test("ignores a --model flag with no value")
    func danglingArgument() {
        #expect(
            ClaudeCodeModelSelection.model(fromArguments: ["claude", "--model"])
                == nil
        )
    }

    @Test("falls back through local, project, then user settings")
    func settingsPrecedence() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.writeUserSettings(#"{"model":"haiku"}"#)
        #expect(fixture.resolve() == "haiku")

        try fixture.writeProjectSettings(#"{"model":"sonnet"}"#)
        #expect(fixture.resolve() == "sonnet")

        try fixture.writeProjectLocalSettings(#"{"model":"opus[1m]"}"#)
        #expect(fixture.resolve() == "opus[1m]")
    }

    @Test("skips settings files that are malformed or carry no usable model")
    func toleratesUnusableSettings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeUserSettings(#"{"model":"opus[1m]"}"#)

        try fixture.writeProjectLocalSettings("{not json")
        #expect(fixture.resolve() == "opus[1m]")

        try fixture.writeProjectLocalSettings(#"{"permissions":{}}"#)
        #expect(fixture.resolve() == "opus[1m]")

        try fixture.writeProjectLocalSettings(#"{"model":42}"#)
        #expect(fixture.resolve() == "opus[1m]")

        try fixture.writeProjectLocalSettings(#"{"model":""}"#)
        #expect(fixture.resolve() == "opus[1m]")
    }

    @Test("returns nil when nothing on disk names a model")
    func noSelection() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(fixture.resolve() == nil)
        #expect(fixture.resolve(arguments: ["claude", "--resume"]) == nil)
    }

    @Test("tolerates a working directory that does not exist")
    func missingWorkingDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeUserSettings(#"{"model":"opus[1m]"}"#)

        #expect(
            ClaudeCodeModelSelection.resolve(
                arguments: [],
                workingDirectory: fixture.root
                    .appendingPathComponent("gone", isDirectory: true),
                claudeHome: fixture.claudeHome
            ) == "opus[1m]"
        )
        #expect(
            ClaudeCodeModelSelection.resolve(
                arguments: [],
                workingDirectory: nil,
                claudeHome: fixture.claudeHome
            ) == "opus[1m]"
        )
    }
}
