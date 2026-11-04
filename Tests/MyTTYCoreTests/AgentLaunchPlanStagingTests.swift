import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent launch plan: staging long launch lines")
struct AgentLaunchPlanStagingTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("staging-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private func longReview(task: String = "do the thing") -> String {
        AgentLaunchPlan.initialInput(
            provider: .antigravity,
            access: .review,
            model: "gemini-4-argon-medium",
            workingDirectory: "/work/repo",
            task: task
        )
    }

    @Test("a long agy review launch is staged into a short typed line")
    func longLaunchIsShort() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let raw = longReview()
        #expect(raw.utf8.count > AgentLaunchPlan.maxInlineInputBytes)
        let staged = AgentLaunchPlan.staged(raw, in: dir)
        #expect(staged.utf8.count <= AgentLaunchPlan.maxInlineInputBytes)
        #expect(staged.hasPrefix(AgentLaunchPlan.historySuppressionPrefix))
        #expect(staged.hasSuffix("\n"))
    }

    @Test("a very long task is staged too, whatever the provider")
    func longTaskIsStaged() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        for provider in [AgentWorkerProvider.codex, .claude, .cursor, .antigravity] {
            let raw = AgentLaunchPlan.initialInput(
                provider: provider, access: .review, model: nil,
                workingDirectory: "/work/repo",
                task: String(repeating: "x", count: 5000)
            )
            let staged = AgentLaunchPlan.staged(raw, in: dir)
            #expect(staged.utf8.count <= AgentLaunchPlan.maxInlineInputBytes)
        }
    }

    @Test("a short launch is left untouched")
    func shortUnchanged() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let raw = AgentLaunchPlan.initialInput(command: "echo hi")
        #expect(AgentLaunchPlan.staged(raw, in: dir) == raw)
    }

    @Test("sourcing the staged line runs the original command and removes the script")
    func stagedLineRuns() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = "it's a 'quoted'\nmultiline " + String(repeating: "y", count: 2000)
        let raw = AgentLaunchPlan.initialInput(
            command: "printf '%s' \(ShellQuoting.quote(task))"
        )
        let staged = AgentLaunchPlan.staged(raw, in: dir)
        #expect(staged != raw)
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(before.count == 1)
        let mode = { (path: String) -> Int in
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return (attrs?[.posixPermissions] as? Int) ?? -1
        }
        #expect(mode(dir.path) == 0o700)
        #expect(mode(dir.appendingPathComponent(before[0]).path) == 0o600)
        let line = String(
            staged.dropFirst(AgentLaunchPlan.historySuppressionPrefix.count)
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", line]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(decoding: out, as: UTF8.self) == task)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(left.isEmpty)
    }

    @Test("a staging directory that is not private is not trusted")
    func untrustedDirectoryFallsBack() throws {
        let parent = try scratch()
        defer { try? FileManager.default.removeItem(at: parent) }
        let raw = longReview()
        // Too-open mode.
        let open = parent.appendingPathComponent("open")
        try FileManager.default.createDirectory(
            at: open, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        #expect(AgentLaunchPlan.staged(raw, in: open) == raw)
        // Symlink to a private directory.
        let real = parent.appendingPathComponent("real")
        try FileManager.default.createDirectory(
            at: real, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(AgentLaunchPlan.staged(raw, in: link) == raw)
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path).isEmpty)
    }

    @Test("only stale launch scripts are swept")
    func sweepsOnlyStaleScripts() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = AgentLaunchPlan.staged(longReview(), in: dir)
        let fm = FileManager.default
        let old = dir.appendingPathComponent("launch-old.sh")
        let other = dir.appendingPathComponent("keep-old.txt")
        for url in [old, other] {
            fm.createFile(atPath: url.path, contents: Data())
            try fm.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-172_800)],
                ofItemAtPath: url.path
            )
        }
        let fresh = dir.appendingPathComponent("launch-fresh.sh")
        fm.createFile(atPath: fresh.path, contents: Data())
        _ = AgentLaunchPlan.staged(longReview(), in: dir)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(fm.fileExists(atPath: other.path))
        #expect(fm.fileExists(atPath: fresh.path))
    }

    @Test("an unwritable directory falls back to the original input")
    func unwritableFallsBack() throws {
        let parent = try scratch()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: parent.path
            )
            try? FileManager.default.removeItem(at: parent)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: parent.path
        )
        let raw = longReview()
        #expect(
            AgentLaunchPlan.staged(raw, in: parent.appendingPathComponent("sub"))
                == raw
        )
    }
}
