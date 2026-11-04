import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent launch plan: staging long launch lines")
struct AgentLaunchPlanStagingTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("staging-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
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
}
