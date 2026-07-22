import Darwin
import Foundation
import MyTTYCore

struct TerminalAgentDisplay: Equatable {
    let provider: AgentProvider

    static func resolve(foregroundProvider: AgentProvider?) -> TerminalAgentDisplay? {
        guard let foregroundProvider else { return nil }
        return TerminalAgentDisplay(provider: foregroundProvider)
    }
}

struct TerminalAgentLifecycle: Equatable {
    let provider: AgentProvider
    let state: AgentRunState
}

struct TerminalAgentPollActions: Equatable {
    let refreshPresentation: Bool
    let refreshUsage: Bool

    static func make(
        providersChanged: Bool,
        sessionIDsChanged: Bool
    ) -> Self {
        TerminalAgentPollActions(
            refreshPresentation: providersChanged || sessionIDsChanged,
            refreshUsage: true
        )
    }
}

enum TerminalTabAgentActivity {
    static func isProcessing(
        surfaceIDs: [TerminalSurfaceID],
        foregroundProvidersBySurface: [TerminalSurfaceID: AgentProvider],
        lifecycleBySurface: [TerminalSurfaceID: TerminalAgentLifecycle]
    ) -> Bool {
        surfaceIDs.contains { surfaceID in
            guard let foregroundProvider = foregroundProvidersBySurface[surfaceID],
                  let lifecycle = lifecycleBySurface[surfaceID]
            else { return false }
            return lifecycle.provider == foregroundProvider
                && lifecycle.state == .running
        }
    }
}

enum TerminalAgentProcessDetector {
    static func commandName(processID: pid_t) -> String? {
        guard processID > 0 else { return nil }
        return executablePath(processID: processID).flatMap {
            commandName(executablePath: $0)
        }
    }

    static func commandName(executablePath: String) -> String? {
        guard !executablePath.isEmpty else { return nil }
        let name = URL(fileURLWithPath: executablePath).lastPathComponent
        return name.isEmpty ? nil : name
    }

    static func provider(processID: pid_t) -> AgentProvider? {
        guard processID > 0,
              let executablePath = executablePath(processID: processID)
        else { return nil }
        return provider(
            executablePath: executablePath,
            arguments: arguments(processID: processID)
        )
    }

    static func resumeKind(processID: pid_t) -> AgentResumeKind? {
        guard processID > 0,
              let executablePath = executablePath(processID: processID)
        else { return nil }
        let processArguments = arguments(processID: processID)
        guard let provider = provider(
            executablePath: executablePath,
            arguments: processArguments
        ) else { return nil }
        return AgentResumeLaunchPlan.kind(
            provider: provider,
            executablePath: executablePath,
            arguments: processArguments
        )
    }

    static func provider(
        executablePath: String,
        arguments: [String]
    ) -> AgentProvider? {
        let launchTokens = [executablePath] + arguments.prefix(2)
        let normalized = launchTokens.map { $0.lowercased() }
        let basenames = Set(normalized.map {
            URL(fileURLWithPath: $0).lastPathComponent
        })
        let invocation = normalized.joined(separator: "\u{0}")

        if basenames.contains("cursor-agent")
            || invocation.contains("/cursor-agent/") {
            return .cursor
        }
        if basenames.contains("agy")
            || basenames.contains("antigravity")
            || invocation.contains("/antigravity/") {
            return .antigravity
        }
        if basenames.contains("claude")
            || basenames.contains("claude-code")
            || invocation.contains("/claude-code/") {
            return .claudeCode
        }
        if basenames.contains("opencode")
            || invocation.contains("/opencode/") {
            return .openCode
        }
        if basenames.contains("codex")
            || basenames.contains(where: { $0.hasPrefix("codex-") })
            || invocation.contains("/@openai/codex/") {
            return .codex
        }
        if basenames.contains("gemini")
            || basenames.contains("gemini-cli")
            || invocation.contains("/gemini-cli/") {
            return .antigravity
        }
        return nil
    }

    /// The executable path and argv for a running process, exposed
    /// together (rather than via the private helpers below individually)
    /// for callers that need both to resolve a provider *and* inspect its
    /// launch flags — e.g. `agent spawn --access inherit`, which reads the
    /// anchor pane's foreground process to copy its mode flags onto a new
    /// worker. Returns `nil` when the process can't be resolved at all.
    static func invocation(
        processID: pid_t
    ) -> (executablePath: String, arguments: [String])? {
        guard processID > 0,
              let executablePath = executablePath(processID: processID)
        else { return nil }
        return (executablePath, arguments(processID: processID))
    }

    private static func executablePath(processID: pid_t) -> String? {
        var buffer = [CChar](
            repeating: 0,
            count: Int(MAXPATHLEN) * 4
        )
        let length = proc_pidpath(
            processID,
            &buffer,
            UInt32(buffer.count)
        )
        guard length > 0 else { return nil }
        return String(
            decoding: buffer.prefix(Int(length)).map(UInt8.init(bitPattern:)),
            as: UTF8.self
        )
    }

    private static func arguments(processID: pid_t) -> [String] {
        var query = [CTL_KERN, KERN_PROCARGS2, processID]
        var size = 0
        guard sysctl(&query, UInt32(query.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size
        else { return [] }

        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&query, UInt32(query.count), &bytes, &size, nil, 0) == 0
        else { return [] }
        bytes = Array(bytes.prefix(size))

        var argumentCount: Int32 = 0
        withUnsafeMutableBytes(of: &argumentCount) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(
                    from: source.prefix(MemoryLayout<Int32>.size)
                )
            }
        }

        var index = MemoryLayout<Int32>.size
        skipString(in: bytes, index: &index)
        skipNulls(in: bytes, index: &index)

        var result: [String] = []
        result.reserveCapacity(Int(max(argumentCount, 0)))
        while index < bytes.count, result.count < argumentCount {
            let start = index
            skipString(in: bytes, index: &index)
            if start < index,
               let value = String(bytes: bytes[start..<index], encoding: .utf8) {
                result.append(value)
            }
            skipNulls(in: bytes, index: &index)
        }
        return result
    }

    private static func skipString(in bytes: [UInt8], index: inout Int) {
        while index < bytes.count, bytes[index] != 0 {
            index += 1
        }
    }

    private static func skipNulls(in bytes: [UInt8], index: inout Int) {
        while index < bytes.count, bytes[index] == 0 {
            index += 1
        }
    }
}
