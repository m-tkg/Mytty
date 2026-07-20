import Foundation
import MyTTYCore

struct NativeAgentUsageLoader: AgentUsageLoading {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let pathProfile: ApplicationPathProfile

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        pathProfile: ApplicationPathProfile = ApplicationIdentity.pathProfile
    ) {
        self.environment = environment
        self.pathProfile = pathProfile
        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.homeDirectory = URL(fileURLWithPath: home, isDirectory: true)
    }

    func loadSummary(for provider: AgentProvider) async -> AgentUsageSummary? {
        guard let source = AgentProviderUsageRegistry.source(for: provider)
        else { return nil }
        return await source.loadSummary(
            homeDirectory: homeDirectory,
            pathProfile: pathProfile,
            environment: environment
        )
    }

    static func providerIdentifier(for provider: AgentProvider) -> String {
        switch provider {
        case .codex: "codex"
        case .claudeCode: "claude"
        case .openCode: "opencode"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        }
    }
}

/// One implementation per agent provider for the piece of `loadSummary(for:)`
/// that used to be a `switch` case: how to fetch that provider's usage data
/// and turn it into an `AgentUsageSummary`. Kept in this file (rather than
/// alongside `AgentProviderRuntime`) because it stays off the main actor —
/// `AgentUsageCache` is a plain (non-`@MainActor`) actor, and these sources
/// do their I/O (network requests, subprocess calls, SQLite reads) on its
/// executor, not the main thread.
protocol AgentProviderUsageSource: Sendable {
    var provider: AgentProvider { get }

    func loadSummary(
        homeDirectory: URL,
        pathProfile: ApplicationPathProfile,
        environment: [String: String]
    ) async -> AgentUsageSummary?
}

enum AgentProviderUsageRegistry {
    static let sources: [any AgentProviderUsageSource] = [
        CodexUsageSource(),
        ClaudeCodeUsageSource(),
        AntigravityUsageSource(),
        CursorUsageSource(),
        OpenCodeUsageSource(),
    ]

    private static let byProvider: [AgentProvider: any AgentProviderUsageSource] =
        Dictionary(uniqueKeysWithValues: sources.map { ($0.provider, $0) })

    static func source(for provider: AgentProvider) -> (any AgentProviderUsageSource)? {
        byProvider[provider]
    }
}

struct CodexUsageSource: AgentProviderUsageSource {
    let provider: AgentProvider = .codex

    func loadSummary(
        homeDirectory: URL,
        pathProfile: ApplicationPathProfile,
        environment: [String: String]
    ) async -> AgentUsageSummary? {
        async let cost = AgentSessionCostScanner.latestCost(
            for: .codex,
            homeDirectory: homeDirectory
        )
        let data = await CodexRateLimitProbe(environment: environment).fetch()
        let sessionCost = await cost
        guard let data else {
            return NativeAgentUsageParser.costOnly(sessionCost)
        }
        return (try? NativeAgentUsageParser.codexSummary(
            from: data,
            sessionCostUSD: sessionCost
        )) ?? NativeAgentUsageParser.costOnly(sessionCost)
    }
}

struct ClaudeCodeUsageSource: AgentProviderUsageSource {
    let provider: AgentProvider = .claudeCode

    func loadSummary(
        homeDirectory: URL,
        pathProfile: ApplicationPathProfile,
        environment: [String: String]
    ) async -> AgentUsageSummary? {
        async let cost = AgentSessionCostScanner.latestCost(
            for: .claudeCode,
            homeDirectory: homeDirectory
        )
        let cacheURL = ClaudeUsageProbe.cacheURL(
            homeDirectory: homeDirectory,
            pathProfile: pathProfile
        )
        let result = await ClaudeUsageProbe.fetch(
            homeDirectory: homeDirectory,
            cacheURL: cacheURL
        )
        let sessionCost = await cost
        if case let .success(data) = result {
            do {
                let summary = try NativeAgentUsageParser.claudeSummary(
                    from: data,
                    sessionCostUSD: sessionCost
                )
                await ClaudeUsageResilienceStore.shared.recordLimits(
                    summary?.limits ?? [],
                    cacheURL: cacheURL
                )
                return summary
            } catch {
                await ClaudeUsageResilienceStore.shared.recordFailure(
                    cacheURL: cacheURL
                )
            }
        }
        let cachedLimits = await ClaudeUsageResilienceStore.shared
            .cachedLimits(cacheURL: cacheURL)
        return Self.fallbackSummary(
            sessionCostUSD: sessionCost,
            limits: cachedLimits
        )
    }

    private static func fallbackSummary(
        sessionCostUSD: Double?,
        limits: [AgentUsageLimit]
    ) -> AgentUsageSummary? {
        let cost = sessionCostUSD.map {
            AgentUsageCost.session(amount: $0, currencyCode: "USD")
        }
        guard cost != nil || !limits.isEmpty else { return nil }
        return AgentUsageSummary(cost: cost, limits: limits, limitsAreStale: true)
    }
}

struct AntigravityUsageSource: AgentProviderUsageSource {
    let provider: AgentProvider = .antigravity

    func loadSummary(
        homeDirectory: URL,
        pathProfile: ApplicationPathProfile,
        environment: [String: String]
    ) async -> AgentUsageSummary? {
        guard let data = await AntigravityUsageProbe.fetch() else {
            return nil
        }
        return try? NativeAgentUsageParser.antigravitySummary(from: data)
    }
}

struct CursorUsageSource: AgentProviderUsageSource {
    let provider: AgentProvider = .cursor

    func loadSummary(
        homeDirectory: URL,
        pathProfile: ApplicationPathProfile,
        environment: [String: String]
    ) async -> AgentUsageSummary? {
        guard let data = await CursorUsageProbe.fetch(
            homeDirectory: homeDirectory
        ) else { return nil }
        return try? NativeAgentUsageParser.cursorSummary(from: data)
    }
}

struct OpenCodeUsageSource: AgentProviderUsageSource {
    let provider: AgentProvider = .openCode

    func loadSummary(
        homeDirectory: URL,
        pathProfile: ApplicationPathProfile,
        environment: [String: String]
    ) async -> AgentUsageSummary? {
        await OpenCodeUsageProbe.fetch(homeDirectory: homeDirectory)
    }
}

private final class CodexRateLimitProbe: @unchecked Sendable {
    private let environment: [String: String]

    init(environment: [String: String]) {
        self.environment = environment
    }

    func fetch() async -> Data? {
        await Task.detached(priority: .utility) {
            self.fetchSynchronously()
        }.value
    }

    private func fetchSynchronously() -> Data? {
        guard let executable = Self.resolveCodex(environment: environment) else {
            return nil
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let response = RPCResponseBox(expectedID: 2)

        process.executableURL = executable
        process.arguments = ["app-server"]
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                response.append(data)
            }
        }
        process.terminationHandler = { _ in response.finish() }

        do {
            try process.run()
            for payload in Self.requests {
                try input.fileHandleForWriting.write(contentsOf: payload)
                try input.fileHandleForWriting.write(contentsOf: Data([0x0A]))
            }
            _ = response.wait(timeout: 6)
        } catch {
            response.finish()
        }

        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        return response.result
    }

    private static let requests: [Data] = [
        #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"mytty","version":"0.1.0"}}}"#,
        #"{"method":"initialized","params":{}}"#,
        #"{"id":2,"method":"account/rateLimits/read","params":{}}"#,
    ].compactMap { $0.data(using: .utf8) }

    private static func resolveCodex(environment: [String: String]) -> URL? {
        let home = environment["HOME"] ?? NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        candidates.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/codex" })
        return candidates.lazy
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private final class RPCResponseBox: @unchecked Sendable {
    private let expectedID: Int
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var storedResult: Data?
    private var didFinish = false

    init(expectedID: Int) {
        self.expectedID = expectedID
    }

    var result: Data? {
        lock.withLock { storedResult }
    }

    func append(_ data: Data) {
        lock.withLock {
            guard storedResult == nil else { return }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? NSNumber)?.intValue == expectedID,
                      let value = object["result"],
                      JSONSerialization.isValidJSONObject(value),
                      let encoded = try? JSONSerialization.data(withJSONObject: value)
                else { continue }
                storedResult = encoded
                signalOnce()
                return
            }
        }
    }

    func finish() {
        lock.withLock { signalOnce() }
    }

    func wait(timeout: TimeInterval) -> Bool {
        semaphore.wait(timeout: .now() + timeout) == .success
    }

    private func signalOnce() {
        guard !didFinish else { return }
        didFinish = true
        semaphore.signal()
    }
}

private enum ClaudeUsageProbeResult: Sendable {
    case success(Data)
    case deferred
}

private enum ClaudeUsageProbe {
    static func cacheURL(
        homeDirectory: URL,
        pathProfile: ApplicationPathProfile
    ) -> URL {
        ApplicationPaths(
            homeDirectory: homeDirectory,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            profile: pathProfile
        )
        .applicationSupportDirectory
        .appending(path: "claude-usage-cache.json")
    }

    static func fetch(
        homeDirectory: URL,
        cacheURL: URL,
        now: Date = Date()
    ) async -> ClaudeUsageProbeResult {
        var token = ClaudeCredentialStore.accessToken(homeDirectory: homeDirectory)
        if token == nil,
           let payload = await ClaudeCredentialStore.keychainPayload()
        {
            token = ClaudeCredentialStore.accessToken(
                homeDirectory: homeDirectory,
                keychainPayload: payload
            )
        }
        guard let token,
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage")
        else { return .deferred }
        guard await ClaudeUsageResilienceStore.shared.beginRequest(
            cacheURL: cacheURL,
            now: now
        ) else { return .deferred }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse
        else {
            await ClaudeUsageResilienceStore.shared.recordFailure(
                cacheURL: cacheURL
            )
            return .deferred
        }
        switch response.statusCode {
        case 200:
            return .success(data)
        case 429:
            await ClaudeUsageResilienceStore.shared.recordRateLimit(
                retryAfter: retryAfterDate(from: response, now: now),
                cacheURL: cacheURL,
                now: now
            )
            return .deferred
        default:
            await ClaudeUsageResilienceStore.shared.recordFailure(
                cacheURL: cacheURL
            )
            return .deferred
        }
    }

    private static func retryAfterDate(
        from response: HTTPURLResponse,
        now: Date
    ) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value)
    }
}

enum ClaudeCredentialStore {
    static func accessToken(
        homeDirectory: URL,
        keychainPayload: Data? = nil
    ) -> String? {
        let url = homeDirectory
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: ".credentials.json")
        if let data = try? Data(contentsOf: url),
           let token = accessToken(from: data)
        {
            return token
        }
        return keychainPayload.flatMap(accessToken(from:))
    }

    static func keychainPayload() async -> Data? {
        guard let output = await NativeUsageProcessRunner.capture(
            executable: "/usr/bin/security",
            arguments: [
                "find-generic-password",
                "-s", "Claude Code-credentials",
                "-w",
            ],
            timeout: 1.5
        ) else { return nil }
        return Data(output.utf8)
    }

    private static func accessToken(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        if let expiresAt = oauth["expiresAt"] as? NSNumber,
           expiresAt.doubleValue / 1_000 <= Date().timeIntervalSince1970 {
            return nil
        }
        return token
    }
}
