import Foundation
import MyTTYCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Evaluation harness for the one-liner composer, modeled on the
/// "measure before tuning" workflow: 25 tasks run against the real
/// on-device model, each generated command executed in a throwaway
/// fixture tree and judged by behavior. Run with
/// `swift run mytty-oneliner-eval` (add `--think` for the two-gear
/// reasoning variant, `--case <id>` to focus one task).
@main
struct Entry {
    static func main() async {
        var useThink = false
        var onlyCase: String?
        var runs = 1
        var args = Array(CommandLine.arguments.dropFirst())
        while let arg = args.first {
            args.removeFirst()
            switch arg {
            case "--think": useThink = true
            case "--case": onlyCase = args.isEmpty ? nil : args.removeFirst()
            case "--runs":
                runs = args.isEmpty ? 1 : Int(args.removeFirst()) ?? 1
            default:
                FileHandle.standardError.write(
                    Data("unknown argument: \(arg)\n".utf8)
                )
                exit(2)
            }
        }

        guard #available(macOS 26, *) else {
            print("requires macOS 26+ (Foundation Models)")
            exit(1)
        }
        let cases = evalCases.filter { onlyCase == nil || $0.id == onlyCase }
        guard !cases.isEmpty else {
            print("no case named \(onlyCase ?? "")")
            exit(2)
        }
        // The on-device model is not deterministic run to run even with
        // greedy sampling, so single runs cannot compare prompt
        // variants — aggregate over --runs N.
        var passCounts: [String: Int] = [:]
        for runIndex in 1...max(1, runs) {
            if runs > 1 { print("--- run \(runIndex)/\(runs) ---") }
            let passes = await run(cases: cases, think: useThink)
            for id in passes { passCounts[id, default: 0] += 1 }
        }
        if runs > 1 {
            print("\n=== aggregate over \(runs) runs ===")
            var totalRate = 0.0
            for evalCase in cases {
                let count = passCounts[evalCase.id, default: 0]
                totalRate += Double(count)
                let flag = count == runs ? "" : count == 0 ? "  ✗" : "  ~"
                print("  \(evalCase.id): \(count)/\(runs)\(flag)")
            }
            let mean = totalRate / Double(cases.count * runs) * 100
            print(String(format: "mean accuracy: %.0f%%", mean))
        }
    }

    /// Runs every case once; returns the ids that passed.
    @available(macOS 26, *)
    @discardableResult
    static func run(cases: [EvalCase], think: Bool) async -> [String] {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else {
            print(
                "model unavailable: \(SystemLanguageModel.default.availability)"
            )
            exit(1)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mytty-oneliner-eval-fixture")
        var results: [(EvalCase, Verdict)] = []
        print("=== mode: \(think ? "think" : "fast") ===")
        for evalCase in cases {
            let started = Date()
            let command = await generate(task: evalCase.task, think: think)
            let seconds = String(
                format: "%.1fs", Date().timeIntervalSince(started)
            )
            let verdict: Verdict
            if let command {
                verdict = judge(
                    command: command, evalCase: evalCase, fixtureRoot: root
                )
            } else {
                verdict = .init(category: .refusal, command: "(no command)")
            }
            results.append((evalCase, verdict))
            let mark = verdict.category == .pass ? "PASS" : "FAIL"
            print("[\(mark)] \(evalCase.id) (\(seconds))")
            print("    task: \(evalCase.task)")
            print("    got:  \(verdict.command)")
            if verdict.category != .pass {
                print("    ref:  \(evalCase.reference)")
                print("    why:  \(verdict.category.rawValue)"
                    + (verdict.detail.map { " — \($0)" } ?? ""))
            }
        }
        try? FileManager.default.removeItem(at: root)
        let passed = results.filter { $0.1.category == .pass }.count
        print("\n\(passed)/\(results.count) passed")
        let failures = Dictionary(
            grouping: results.filter { $0.1.category != .pass },
            by: { $0.1.category }
        )
        for (category, members) in failures
            .sorted(by: { $0.value.count > $1.value.count }) {
            let ids = members.map { $0.0.id }.joined(separator: ", ")
            print("  \(category.rawValue): \(members.count) (\(ids))")
        }
        return results.filter { $0.1.category == .pass }.map { $0.0.id }
        #else
        return []
        #endif
    }

    // MARK: - Generation

    @available(macOS 26, *)
    static func generate(task: String, think: Bool) async -> String? {
        #if canImport(FoundationModels)
        let instructions = think
            ? thinkInstructions
            : OneLinerPrompt.instructions(language: .japanese)
        // Default guardrails false-positive on harmless Japanese tasks
        // ("1MB より大きいファイルを探す"); the reply is only ever copied
        // by the user, never executed, so the permissive transform
        // guardrails are appropriate.
        let session = LanguageModelSession(
            model: SystemLanguageModel(
                guardrails: .permissiveContentTransformations
            ),
            instructions: instructions
        )
        let response: LanguageModelSession.Response<String>
        // On Xcode 27 the deprecated `sampling:` label is silently ignored
        // (random sampling); the Xcode 26 SDK on CI only has `sampling:`.
        #if compiler(>=6.4)
        let options = GenerationOptions(
            samplingMode: .greedy,
            maximumResponseTokens: think ? 600 : 200
        )
        #else
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: think ? 600 : 200
        )
        #endif
        do {
            response = try await session.respond(
                to: OneLinerPrompt.prompt(request: task),
                options: options
            )
        } catch {
            print("    respond() threw: \(error)")
            return nil
        }
        if think {
            let lines = response.content.split(separator: "\n")
            guard let final = lines.last(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("COMMAND:")
            }) else { return nil }
            return OneLinerPrompt.sanitize(
                String(
                    final.trimmingCharacters(in: .whitespaces)
                        .dropFirst("COMMAND:".count)
                )
            )
        }
        return OneLinerPrompt.sanitize(response.content)
        #else
        return nil
        #endif
    }

    /// The "second gear": same decision rules as production, but the
    /// model is told to reason first and mark the final answer, at a
    /// higher token budget.
    static let thinkInstructions = """
    You write shell one-liners for macOS (zsh). First think through \
    the task step by step: is it about file CONTENTS or file NAMES, \
    which strings are literal, is anything excluded. Keep the \
    reasoning short. Then output the final answer as the LAST line, \
    in exactly this form:
    COMMAND: <the one-liner>

    Decision rules:
    - Searching file CONTENTS (中身, 内容, ファイル内): use grep \
    recursively. NEVER use find -name for contents.
    - Searching file NAMES (ファイル名): use find -name.
    - Always single-quote search patterns. Search strings from the \
    task are literal text — copy them exactly, never invent \
    character classes.
    - Only when the task EXCLUDES something (〜は含まない, 〜を除く, \
    "but not"), pipe into grep -v with the excluded string. \
    Otherwise never add grep -v.

    Examples of final lines:
    COMMAND: find . -type f -name '*log*'
    COMMAND: grep -r '^foo' . | grep -v 'foobar'

    If the task cannot be done in one command line, make the last \
    line: COMMAND: none
    """

    // MARK: - Judging

    enum FailureCategory: String {
        case pass
        case refusal
        case unsafe = "unsafe-skipped"
        case timeout
        case wrongOutput = "wrong-output"
    }

    struct Verdict {
        var category: FailureCategory
        var command: String
        var detail: String?
    }

    static let deniedFragments = [
        "sudo", "rm -rf /", "mkfs", "shutdown", "reboot",
        "curl", "wget", "dd if=", "> /dev", ":(){", "$HOME", "~/",
    ]

    static func judge(
        command: String, evalCase: EvalCase, fixtureRoot: URL
    ) -> Verdict {
        if command == "none" || deniedFragments.contains(
            where: { command.contains($0) }
        ) {
            return .init(
                category: command == "none" ? .refusal : .unsafe,
                command: command
            )
        }
        // A sentence instead of a command counts as a refusal.
        if command.unicodeScalars.contains(where: {
            (0x3040...0x30FF).contains($0.value)
        }), !command.contains("'") {
            return .init(category: .refusal, command: command)
        }
        do {
            try EvalFixture.build(at: fixtureRoot)
        } catch {
            return .init(
                category: .wrongOutput, command: command,
                detail: "fixture build failed: \(error)"
            )
        }
        guard let stdout = execute(command, in: fixtureRoot) else {
            return .init(category: .timeout, command: command)
        }
        let ok = matches(
            stdout: stdout, expectation: evalCase.expectation,
            fixtureRoot: fixtureRoot
        )
        return .init(
            category: ok ? .pass : .wrongOutput,
            command: command,
            detail: ok ? nil : "stdout: "
                + stdout.replacingOccurrences(of: "\n", with: " ⏎ ")
                    .prefix(200)
        )
    }

    /// Runs the command with zsh in the fixture directory. Returns nil
    /// on timeout (10s).
    static func execute(_ command: String, in dir: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -f skips rc files: the harness must not inherit whatever the
        // developer's shell init does.
        process.arguments = ["-f", "-c", command]
        process.currentDirectoryURL = dir
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // A command that reads stdin (e.g. a bare grep with no file)
        // must fail fast instead of hanging until the timeout.
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        let buffer = OutputBuffer()
        out.fileHandleForReading.readabilityHandler = { handle in
            buffer.append(handle.availableData)
        }
        // Drain stderr so a chatty command can't fill the pipe buffer
        // and block forever.
        err.fileHandleForReading.readabilityHandler = {
            _ = $0.availableData
        }
        defer {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
        }
        do { try process.run() } catch { return "" }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return nil
        }
        out.fileHandleForReading.readabilityHandler = nil
        buffer.append(out.fileHandleForReading.readDataToEndOfFile())
        return String(data: buffer.snapshot(), encoding: .utf8) ?? ""
    }

    final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    static func matches(
        stdout: String, expectation: Expectation, fixtureRoot: URL
    ) -> Bool {
        let rawLines = stdout.split(separator: "\n").map(String.init)
        switch expectation {
        case .paths(let expected):
            return Set(rawLines.map(normalizePath)) == expected
                && rawLines.count == expected.count
        case .contentLines(let expected):
            let stripped = rawLines.map {
                stripLocationPrefix($0, fixtureRoot: fixtureRoot)
            }
            return stripped.sorted() == expected.sorted()
        case .orderedLines(let expected):
            return rawLines == expected
        case .count(let expected):
            let first = stdout.split(
                whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }
            ).first
            return first.flatMap { Int($0) } == expected
        case .uniqueSet(let expected):
            let stripped = rawLines.map {
                stripLocationPrefix($0, fixtureRoot: fixtureRoot)
            }
            return Set(stripped) == expected
                && stripped.count == expected.count
        case .fileCreated(let path, let content):
            let url = fixtureRoot.appendingPathComponent(path)
            return (try? String(contentsOf: url, encoding: .utf8)) == content
        case .custom(_, let predicate):
            return predicate(stdout, fixtureRoot)
        }
    }

    static func normalizePath(_ line: String) -> String {
        var path = line.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("./") { path.removeFirst(2) }
        return path
    }

    /// Strips a leading `path:` or `path:linenum:` prefix, but only when
    /// the prefix actually names a fixture file — "error: disk full" has
    /// a colon of its own and must survive intact.
    static func stripLocationPrefix(
        _ line: String, fixtureRoot: URL
    ) -> String {
        let parts = line.split(
            separator: ":", maxSplits: 2, omittingEmptySubsequences: false
        )
        guard parts.count >= 2 else { return line }
        let candidate = normalizePath(String(parts[0]))
        let exists = FileManager.default.fileExists(
            atPath: fixtureRoot.appendingPathComponent(candidate).path
        )
        guard exists else { return line }
        var rest = line.dropFirst(parts[0].count + 1)
        if parts.count == 3, Int(parts[1]) != nil {
            rest = rest.dropFirst(parts[1].count + 1)
        }
        return String(rest)
    }
}
