import Foundation
import Testing

@testable import MyTTYApp

@MainActor
private final class FakeClamshellDaemon: ClamshellDaemonControlling {
    var isApproved = false
    var requiresApproval = false
    var registrationErrorDescription: String?
    var registerCalls = 0
    var openSettingsCalls = 0
    var keepAwakeCalls: [Bool] = []
    var replySuccess = true

    func registerIfNeeded() { registerCalls += 1 }
    func openApprovalSettings() { openSettingsCalls += 1 }
    func setKeepAwake(
        _ enabled: Bool,
        watchedPID: pid_t,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        keepAwakeCalls.append(enabled)
        completion(replySuccess)
    }
}

@Suite("Clamshell sleep blocker")
struct ClamshellSleepBlockerTests {
    private static func temporaryFlag() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("clamshell.armed")
    }

    @Test("daemon path arms and disarms without any privileged prompt")
    @MainActor
    func daemonFollowsDesiredState() throws {
        let daemon = FakeClamshellDaemon()
        daemon.isApproved = true
        var prompts = 0
        let blocker = ClamshellSleepBlocker(
            flagURL: Self.temporaryFlag(),
            watchedPID: 4242,
            daemon: daemon,
            runPrivileged: { _ in prompts += 1; return true }
        )

        blocker.setDesired(keepAwake: true)
        #expect(blocker.isArmed)
        #expect(daemon.keepAwakeCalls == [true])

        // Same desired state is a no-op, not another XPC call.
        blocker.setDesired(keepAwake: true)
        #expect(daemon.keepAwakeCalls == [true])

        blocker.setDesired(keepAwake: false)
        #expect(!blocker.isArmed)
        #expect(daemon.keepAwakeCalls == [true, false])

        blocker.setDesired(keepAwake: true)
        #expect(blocker.isArmed)
        #expect(daemon.keepAwakeCalls == [true, false, true])
        #expect(prompts == 0)
    }

    @Test("a failed daemon call leaves the blocker disarmed and retries")
    @MainActor
    func daemonFailureDisarms() throws {
        let daemon = FakeClamshellDaemon()
        daemon.isApproved = true
        daemon.replySuccess = false
        let blocker = ClamshellSleepBlocker(
            flagURL: Self.temporaryFlag(),
            watchedPID: 4242,
            daemon: daemon,
            runPrivileged: { _ in true }
        )

        blocker.setDesired(keepAwake: true)
        #expect(!blocker.isArmed)

        // The failure did not latch the requested state: once the daemon
        // recovers, the next apply sends the request again.
        daemon.replySuccess = true
        blocker.setDesired(keepAwake: true)
        #expect(blocker.isArmed)
    }

    @Test("missing approval surfaces the hint; settings open only on user intent")
    @MainActor
    func approvalHint() throws {
        let daemon = FakeClamshellDaemon()
        daemon.isApproved = false
        daemon.requiresApproval = true
        let blocker = ClamshellSleepBlocker(
            flagURL: Self.temporaryFlag(),
            watchedPID: 4242,
            daemon: daemon,
            runPrivileged: { _ in true }
        )

        // Passive activation (e.g. an agent starting) shows the hint but
        // never yanks the user into System Settings.
        blocker.setDesired(keepAwake: true)
        #expect(!blocker.isArmed)
        #expect(blocker.needsBackgroundItemApproval)
        #expect(daemon.openSettingsCalls == 0)
        #expect(daemon.registerCalls > 0)

        // The pending approval stays visible even while no agent keeps
        // sleep prevention active — a selected mode with a silent helper
        // looked broken otherwise.
        blocker.setDesired(keepAwake: false)
        #expect(blocker.needsBackgroundItemApproval)

        // An explicit mode selection first explains the approval; only a
        // confirmed prompt opens System Settings, and only once.
        var prompts = 0
        var promptAnswer = false
        blocker.confirmApprovalPrompt = {
            prompts += 1
            return promptAnswer
        }
        blocker.noteUserIntent()
        blocker.setDesired(keepAwake: true)
        #expect(prompts == 1)
        #expect(daemon.openSettingsCalls == 0)

        promptAnswer = true
        blocker.noteUserIntent()
        blocker.setDesired(keepAwake: true)
        #expect(prompts == 2)
        #expect(daemon.openSettingsCalls == 1)
        blocker.setDesired(keepAwake: true)
        #expect(prompts == 2)
        #expect(daemon.openSettingsCalls == 1)

        // The hint clears once the approval is granted.
        daemon.isApproved = true
        daemon.requiresApproval = false
        blocker.setDesired(keepAwake: false)
        #expect(!blocker.needsBackgroundItemApproval)
    }

    @Test("mode selection prompts even before any agent is active")
    @MainActor
    func promptWithoutActiveAgent() throws {
        let daemon = FakeClamshellDaemon()
        daemon.requiresApproval = true
        let blocker = ClamshellSleepBlocker(
            flagURL: Self.temporaryFlag(),
            watchedPID: 4242,
            daemon: daemon,
            runPrivileged: { _ in true }
        )
        var prompts = 0
        blocker.confirmApprovalPrompt = { prompts += 1; return true }

        blocker.noteUserIntent()
        blocker.setDesired(keepAwake: false)
        #expect(prompts == 1)
        #expect(daemon.openSettingsCalls == 1)
    }

    @Test("a registration failure is exposed for the tooltip")
    @MainActor
    func registrationFailureSurfaces() throws {
        let daemon = FakeClamshellDaemon()
        daemon.registrationErrorDescription = "Operation not permitted"
        let blocker = ClamshellSleepBlocker(
            flagURL: Self.temporaryFlag(),
            watchedPID: 4242,
            daemon: daemon,
            runPrivileged: { _ in true }
        )
        #expect(
            blocker.registrationErrorDescription
                == "Operation not permitted"
        )
    }

    @Test("fallback arms once per run, then only touches the flag")
    @MainActor
    func fallbackPromptsOncePerRun() throws {
        let flag = Self.temporaryFlag()
        defer {
            try? FileManager.default.removeItem(
                at: flag.deletingLastPathComponent()
            )
        }
        var scripts: [String] = []
        let blocker = ClamshellSleepBlocker(
            flagURL: flag,
            watchedPID: 4242,
            daemon: nil,
            runPrivileged: { scripts.append($0); return true }
        )

        blocker.setDesired(keepAwake: true)
        #expect(blocker.isArmed)
        #expect(FileManager.default.fileExists(atPath: flag.path))
        #expect(scripts.count == 1)
        #expect(scripts[0].contains("pmset disablesleep $want"))
        #expect(scripts[0].contains("pmset disablesleep 0"))
        #expect(scripts[0].contains("kill -0 4242"))
        #expect(scripts[0].contains(flag.path))

        blocker.setDesired(keepAwake: false)
        #expect(!blocker.isArmed)
        #expect(!FileManager.default.fileExists(atPath: flag.path))

        // Re-arming while the watcher is still alive only recreates the
        // flag — the privileged script (password prompt) never runs again.
        blocker.setDesired(keepAwake: true)
        #expect(blocker.isArmed)
        #expect(FileManager.default.fileExists(atPath: flag.path))
        #expect(scripts.count == 1)
    }

    @Test("a cancelled fallback prompt stays declined until user intent")
    @MainActor
    func cancelledPromptDeclines() {
        let flag = Self.temporaryFlag()
        defer {
            try? FileManager.default.removeItem(
                at: flag.deletingLastPathComponent()
            )
        }
        var prompts = 0
        let blocker = ClamshellSleepBlocker(
            flagURL: flag,
            watchedPID: 4242,
            daemon: nil,
            runPrivileged: { _ in prompts += 1; return false }
        )

        blocker.setDesired(keepAwake: true)
        #expect(!blocker.isArmed)
        #expect(!FileManager.default.fileExists(atPath: flag.path))
        #expect(prompts == 1)

        // Passive re-activation does not nag again...
        blocker.setDesired(keepAwake: false)
        blocker.setDesired(keepAwake: true)
        #expect(prompts == 1)

        // ...but an explicit mode selection retries.
        blocker.noteUserIntent()
        blocker.setDesired(keepAwake: true)
        #expect(prompts == 2)
    }

    @Test("initializing clears a stale flag from an earlier run")
    @MainActor
    func initClearsStaleFlag() throws {
        let flag = Self.temporaryFlag()
        let directory = flag.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: flag.path, contents: nil)

        _ = ClamshellSleepBlocker(
            flagURL: flag,
            watchedPID: 4242,
            daemon: FakeClamshellDaemon(),
            runPrivileged: { _ in true }
        )
        #expect(!FileManager.default.fileExists(atPath: flag.path))
    }

    @Test("the watcher follows the flag: restore on removal, re-enable on re-creation")
    func watcherFollowsFlag() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // Stub pmset that records its invocations.
        let log = directory.appendingPathComponent("pmset.log")
        let stub = directory.appendingPathComponent("pmset")
        try "#!/bin/sh\necho \"$@\" >> \"\(log.path)\"\n"
            .write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: stub.path
        )
        let flag = directory.appendingPathComponent("clamshell.armed")
        FileManager.default.createFile(atPath: flag.path, contents: nil)

        // The watcher outlives flag removal (so re-arming needs no new
        // privileged launch); tie its lifetime to a disposable child
        // process instead of the test runner.
        let watched = Process()
        watched.executableURL = URL(fileURLWithPath: "/bin/sleep")
        watched.arguments = ["30"]
        try watched.run()
        defer { watched.terminate() }

        let script = ClamshellSleepBlocker.watcherScript(
            flagPath: flag.path,
            watchedPID: watched.processIdentifier,
            pollSeconds: 0.1
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(directory.path):"
            + (environment["PATH"] ?? "")
        process.environment = environment
        try process.run()
        process.waitUntilExit()

        func logLines() -> [String] {
            (try? String(contentsOf: log, encoding: .utf8))
                .map { $0.split(separator: "\n").map(String.init) } ?? []
        }
        func waitFor(
            _ predicate: @escaping ([String]) -> Bool
        ) async throws -> Bool {
            for _ in 0..<100 {
                if predicate(logLines()) { return true }
                try await Task.sleep(for: .milliseconds(50))
            }
            return false
        }

        // Enabled promptly while the flag exists...
        #expect(try await waitFor { $0.contains("disablesleep 1") })
        // ...restored once the flag is removed (watcher keeps running)...
        try FileManager.default.removeItem(at: flag)
        #expect(try await waitFor { $0.contains("disablesleep 0") })
        // ...and enabled again when the flag reappears, with no new
        // privileged launch.
        FileManager.default.createFile(atPath: flag.path, contents: nil)
        #expect(try await waitFor {
            $0.filter { $0 == "disablesleep 1" }.count >= 2
        })
    }
}
