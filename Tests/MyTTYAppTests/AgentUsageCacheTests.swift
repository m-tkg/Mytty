import Foundation
import SQLite3
import Testing

@testable import MyTTYApp
@testable import MyTTYCore

@Suite("Agent usage cache")
struct AgentUsageCacheTests {
    @Test("reuses fresh usage and refreshes expired usage")
    func cacheLifetime() async {
        let loader = AgentUsageLoaderStub()
        let cache = AgentUsageCache(loader: loader, lifetime: 60)
        let start = Date(timeIntervalSince1970: 1_000)

        let first = await cache.summary(for: .codex, now: start)
        let cached = await cache.summary(
            for: .codex,
            now: start.addingTimeInterval(59)
        )
        #expect(first == cached)
        #expect(await loader.loadCount == 1)

        let refreshed = await cache.summary(
            for: .codex,
            now: start.addingTimeInterval(61)
        )
        #expect(refreshed == first)
        #expect(await loader.loadCount == 2)
    }

    @Test("refreshes Claude usage no more than every five minutes")
    func claudeCacheLifetime() async {
        let loader = AgentUsageLoaderStub()
        let cache = AgentUsageCache(loader: loader, lifetime: 60)
        let start = Date(timeIntervalSince1970: 1_000)

        _ = await cache.summary(for: .claudeCode, now: start)
        _ = await cache.summary(
            for: .claudeCode,
            now: start.addingTimeInterval(299)
        )
        #expect(await loader.loadCount == 1)

        _ = await cache.summary(
            for: .claudeCode,
            now: start.addingTimeInterval(300)
        )
        #expect(await loader.loadCount == 2)
    }

    @Test("keeps provider caches independent")
    func providerIsolation() async {
        let loader = AgentUsageLoaderStub()
        let cache = AgentUsageCache(loader: loader, lifetime: 60)
        let now = Date(timeIntervalSince1970: 2_000)

        _ = await cache.summary(for: .codex, now: now)
        _ = await cache.summary(for: .claudeCode, now: now)

        #expect(await loader.loadCount == 2)
    }

    @Test("retries missing usage sooner than successful usage")
    func missingUsageRetry() async {
        let loader = AgentUsageSequenceLoader(results: [nil, AgentUsageSummary(
            cost: nil,
            limits: [AgentUsageLimit(title: "Plan", remainingPercent: 80)]
        )])
        let cache = AgentUsageCache(
            loader: loader,
            lifetime: 60,
            missingLifetime: 2
        )
        let start = Date(timeIntervalSince1970: 3_000)

        #expect(await cache.summary(for: .antigravity, now: start) == nil)
        #expect(await cache.summary(
            for: .antigravity,
            now: start.addingTimeInterval(1)
        ) == nil)
        #expect(await loader.loadCount == 1)

        #expect(await cache.summary(
            for: .antigravity,
            now: start.addingTimeInterval(2)
        )?.limits.first?.remainingPercent == 80)
        #expect(await loader.loadCount == 2)
    }
}

@Suite("Native agent usage adapter")
struct NativeAgentUsageAdapterTests {
    @Test("reads Claude credentials from a local file")
    func claudeCredentialFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let credentials = Data(#"""
        {"claudeAiOauth":{"accessToken":"fixture-token","expiresAt":4102444800000}}
        """#.utf8)
        try credentials.write(to: directory.appending(path: ".credentials.json"))

        #expect(
            ClaudeCredentialStore.accessToken(homeDirectory: home)
                == "fixture-token"
        )
    }

    @Test("falls back to a Claude Keychain payload")
    func claudeCredentialKeychainFallback() {
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let payload = Data(#"""
        {"claudeAiOauth":{"accessToken":"keychain-token","expiresAt":4102444800000}}
        """#.utf8)

        #expect(
            ClaudeCredentialStore.accessToken(
                homeDirectory: home,
                keychainPayload: payload
            ) == "keychain-token"
        )
    }

    @Test("keeps Claude limits while OAuth usage is rate limited")
    func claudeRateLimitFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appending(path: "claude-usage.json")
        let now = Date(timeIntervalSince1970: 10_000)
        let limits = [
            AgentUsageLimit(title: "5h", remainingPercent: 72),
            AgentUsageLimit(title: "7d", remainingPercent: 48),
        ]
        let store = ClaudeUsageResilienceStore(
            defaultCooldown: 300,
            staleLifetime: 86_400
        )

        await store.recordLimits(limits, cacheURL: cacheURL, now: now)
        #expect(
            await store.cachedLimits(cacheURL: cacheURL, now: now) == limits
        )
        #expect(await store.beginRequest(cacheURL: cacheURL, now: now))
        #expect(!(await store.beginRequest(cacheURL: cacheURL, now: now)))

        await store.recordRateLimit(
            retryAfter: nil,
            cacheURL: cacheURL,
            now: now
        )

        #expect(!(await store.beginRequest(
            cacheURL: cacheURL,
            now: now.addingTimeInterval(299)
        )))
        #expect(
            await store.cachedLimits(
                cacheURL: cacheURL,
                now: now.addingTimeInterval(299)
            ) == limits
        )

        let restored = ClaudeUsageResilienceStore(
            defaultCooldown: 300,
            staleLifetime: 86_400
        )
        #expect(
            await restored.cachedLimits(
                cacheURL: cacheURL,
                now: now.addingTimeInterval(299)
            ) == limits
        )
        #expect(!(await restored.beginRequest(
            cacheURL: cacheURL,
            now: now.addingTimeInterval(299)
        )))
        #expect(await restored.beginRequest(
            cacheURL: cacheURL,
            now: now.addingTimeInterval(301)
        ))
        await restored.recordFailure(cacheURL: cacheURL)

        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: cacheURL.path)[
                .posixPermissions
            ] as? Int
        )
        #expect(permissions == 0o600)
    }

    @Test("maps every supported agent to a native provider identifier")
    func providerMapping() {
        #expect(NativeAgentUsageLoader.providerIdentifier(for: .codex) == "codex")
        #expect(NativeAgentUsageLoader.providerIdentifier(for: .claudeCode) == "claude")
        #expect(NativeAgentUsageLoader.providerIdentifier(for: .openCode) == "opencode")
        #expect(NativeAgentUsageLoader.providerIdentifier(for: .antigravity) == "antigravity")
        #expect(NativeAgentUsageLoader.providerIdentifier(for: .cursor) == "cursor")
    }

    @Test("uses compact duration labels for rate windows")
    func rateWindowLabels() {
        #expect(
            NativeAgentUsageParser.limitTitle(
                windowMinutes: 300,
                fallback: "Session"
            ) == "5h"
        )
        #expect(
            NativeAgentUsageParser.limitTitle(
                windowMinutes: 10_080,
                fallback: "Weekly"
            ) == "7d"
        )
        #expect(
            NativeAgentUsageParser.limitTitle(
                windowMinutes: nil,
                fallback: "Pro"
            ) == "Pro"
        )
    }

    @Test("parses Codex rate limits without an external library")
    func codexRateLimits() throws {
        let data = Data(#"""
        {
          "rateLimits": {
            "primary": {"usedPercent": 27, "windowDurationMins": 300},
            "secondary": {"usedPercent": 64, "windowDurationMins": 10080}
          }
        }
        """#.utf8)

        let summary = try NativeAgentUsageParser.codexSummary(
            from: data,
            sessionCostUSD: 1.25
        )

        #expect(summary?.cost == .session(amount: 1.25, currencyCode: "USD"))
        #expect(summary?.limits == [
            AgentUsageLimit(title: "5h", remainingPercent: 73),
            AgentUsageLimit(title: "7d", remainingPercent: 36),
        ])
    }

    @Test("parses Claude OAuth usage windows")
    func claudeRateLimits() throws {
        let data = Data(#"""
        {
          "five_hour": {"utilization": 12.5},
          "seven_day": {"utilization": 60}
        }
        """#.utf8)

        let summary = try NativeAgentUsageParser.claudeSummary(
            from: data,
            sessionCostUSD: 0.75
        )

        #expect(summary?.cost == .session(amount: 0.75, currencyCode: "USD"))
        #expect(summary?.limits == [
            AgentUsageLimit(title: "5h", remainingPercent: 87.5),
            AgentUsageLimit(title: "7d", remainingPercent: 40),
        ])
    }

    @Test("parses current Claude OAuth fallback and scoped limits")
    func claudeCurrentRateLimits() throws {
        let data = Data(#"""
        {
          "five_hour": null,
          "seven_day": null,
          "seven_day_oauth_apps": {"utilization": 25},
          "limits": [
            {
              "kind": "weekly_scoped",
              "percent": 35,
              "scope": {"model": {"display_name": "Sonnet"}}
            }
          ]
        }
        """#.utf8)

        let summary = try NativeAgentUsageParser.claudeSummary(
            from: data,
            sessionCostUSD: nil
        )

        #expect(summary?.cost == nil)
        #expect(summary?.limits == [
            AgentUsageLimit(title: "7d", remainingPercent: 75),
            AgentUsageLimit(title: "Sonnet", remainingPercent: 65),
        ])
    }

    @Test("parses Antigravity quota groups")
    func antigravityRateLimits() throws {
        let data = Data(#"""
        {
          "response": {
            "groups": [
              {
                "displayName": "Gemini Models",
                "buckets": [
                  {"bucketId":"pro","displayName":"Pro","remainingFraction":0.72},
                  {"bucketId":"flash","displayName":"Flash","remainingFraction":0.9}
                ]
              },
              {
                "displayName": "Claude and GPT models",
                "buckets": [
                  {"bucketId":"shared","displayName":"Shared","remaining":{"case":"remainingFraction","value":0.41}}
                ]
              }
            ]
          }
        }
        """#.utf8)

        let summary = try NativeAgentUsageParser.antigravitySummary(from: data)

        #expect(summary?.cost == nil)
        #expect(summary?.limits == [
            AgentUsageLimit(title: "Gemini", remainingPercent: 72),
            AgentUsageLimit(title: "Claude/GPT", remainingPercent: 41),
        ])
    }

    @Test("creates a Cursor usage cookie from Cursor app auth")
    func cursorAppAuthCookie() throws {
        let token = "header."
            + "eyJzdWIiOiJhdXRoMHx1c2VyXzEyMyIsImV4cCI6NDEwMjQ0NDgwMH0"
            + ".signature"

        #expect(
            try CursorCredentialStore.cookieHeader(
                accessToken: token,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            ) == "WorkosCursorSessionToken=user_123%3A%3A\(token)"
        )
    }

    @Test("parses Cursor plan usage and on-demand budget")
    func cursorRateLimits() throws {
        let data = Data(#"""
        {
          "individualUsage": {
            "plan": {
              "totalPercentUsed": 37.5,
              "autoPercentUsed": 20,
              "apiPercentUsed": 60
            },
            "onDemand": {
              "enabled": true,
              "used": 1234,
              "limit": 2000
            }
          }
        }
        """#.utf8)

        let summary = try NativeAgentUsageParser.cursorSummary(from: data)

        #expect(summary?.cost == .budget(
            used: 12.34,
            limit: 20,
            currencyCode: "USD"
        ))
        #expect(summary?.limits == [
            AgentUsageLimit(title: "Plan", remainingPercent: 62.5),
            AgentUsageLimit(title: "Auto", remainingPercent: 80),
            AgentUsageLimit(title: "API", remainingPercent: 40),
        ])
    }

    @Test("calculates OpenCode Go limits from local usage")
    func openCodeGoRateLimits() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home
            .appending(path: ".local/share/opencode", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(#"{"opencode-go":{"type":"api","key":"fixture"}}"#.utf8)
            .write(to: directory.appending(path: "auth.json"))
        let now = Date(timeIntervalSince1970: 1_768_478_400)
        try Self.makeOpenCodeDatabase(
            at: directory.appending(path: "opencode.db"),
            rows: [
                (now.addingTimeInterval(-3_600), "opencode-go", 3),
                (now.addingTimeInterval(-2 * 86_400), "opencode-go", 6),
                (now.addingTimeInterval(-3_600), "anthropic", 20),
            ]
        )

        let summary = await OpenCodeUsageProbe.fetch(
            homeDirectory: home,
            now: now
        )

        #expect(summary?.cost == nil)
        #expect(summary?.limits == [
            AgentUsageLimit(title: "5h", remainingPercent: 75),
            AgentUsageLimit(title: "7d", remainingPercent: 70),
            AgentUsageLimit(title: "Monthly", remainingPercent: 85),
        ])
    }

    @Test("discovers Antigravity CLI and app endpoints")
    func antigravityProcesses() {
        let processList = """
          123 /Users/test/.local/bin/agy
          456 /Applications/Antigravity.app/Contents/language_server \
            --app_data_dir=antigravity --csrf_token csrf-value \
            --extension_server_port 9090 \
            --extension_server_csrf_token extension-value
          789 /usr/bin/unrelated
        """

        #expect(AntigravityUsageProbe.processes(from: processList) == [
            AntigravityUsageProcess(
                processID: 123,
                isCLI: true,
                csrfToken: nil,
                extensionPort: nil,
                extensionToken: nil
            ),
            AntigravityUsageProcess(
                processID: 456,
                isCLI: false,
                csrfToken: "csrf-value",
                extensionPort: 9090,
                extensionToken: "extension-value"
            ),
        ])
        #expect(AntigravityUsageProbe.listeningPorts(from: """
        language_server 456 user 10u IPv4 TCP 127.0.0.1:42123 (LISTEN)
        language_server 456 user 11u IPv6 TCP *:42124 (LISTEN)
        """) == [42123, 42124])
    }

    @Test("calculates the latest Codex session cost from JSONL")
    func codexSessionCost() {
        let data = Data(#"""
        {"type":"turn_context","payload":{"model":"gpt-5.4-mini"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":400000,"output_tokens":100000}}}}
        """#.utf8)

        #expect(AgentSessionCostCalculator.codexCost(from: data) == 0.93)
    }

    @Test("deduplicates streamed Claude usage by message identifier")
    func claudeSessionCost() {
        let data = Data(#"""
        {"type":"assistant","message":{"id":"message-1","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}
        {"type":"assistant","message":{"id":"message-1","model":"claude-sonnet-4-6","usage":{"input_tokens":2000,"cache_creation_input_tokens":1000,"cache_read_input_tokens":3000,"output_tokens":200}}}
        """#.utf8)

        #expect(AgentSessionCostCalculator.claudeCost(from: data) == 0.01365)
    }

    private static func makeOpenCodeDatabase(
        at url: URL,
        rows: [(Date, String, Double)]
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            throw NSError(domain: "OpenCodeFixture", code: 1)
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "CREATE TABLE message (data TEXT, time_created INTEGER);",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw NSError(domain: "OpenCodeFixture", code: 2)
        }
        for (date, provider, cost) in rows {
            let object: [String: Any] = [
                "providerID": provider,
                "role": "assistant",
                "cost": cost,
                "time": ["created": Int64(date.timeIntervalSince1970 * 1_000)],
            ]
            let data = try JSONSerialization.data(withJSONObject: object)
            let json = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "'", with: "''")
            let sql = "INSERT INTO message (data, time_created) VALUES "
                + "('\(json)', \(Int64(date.timeIntervalSince1970 * 1_000)));"
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "OpenCodeFixture", code: 3)
            }
        }
    }
}

@Suite("Active pane agent usage")
struct ActivePaneAgentUsageTests {
    @Test("retries usage while the foreground provider is unchanged")
    func unchangedProviderRetry() {
        #expect(TerminalAgentPollActions.make(
            providersChanged: false,
            sessionIDsChanged: false
        ) == TerminalAgentPollActions(
            refreshPresentation: false,
            refreshUsage: true
        ))
        #expect(TerminalAgentPollActions.make(
            providersChanged: false,
            sessionIDsChanged: true
        ).refreshPresentation)
    }

    @Test("shows usage only for the active pane provider")
    func providerSelection() {
        let summary = AgentUsageSummary(
            cost: .session(amount: 0.5, currencyCode: "USD"),
            limits: []
        )
        #expect(AgentUsageStatusSelection.content(
            activeProvider: .codex,
            loadedProvider: .codex,
            summary: summary
        ) == summary.statusContent())
        #expect(AgentUsageStatusSelection.content(
            activeProvider: .claudeCode,
            loadedProvider: .codex,
            summary: summary
        ) == nil)
        #expect(AgentUsageStatusSelection.content(
            activeProvider: nil,
            loadedProvider: .codex,
            summary: summary
        ) == nil)
    }
}

private actor AgentUsageLoaderStub: AgentUsageLoading {
    private(set) var loadCount = 0

    func loadSummary(for provider: AgentProvider) async -> AgentUsageSummary? {
        loadCount += 1
        return AgentUsageSummary(
            cost: .session(amount: 1, currencyCode: "USD"),
            limits: [
                AgentUsageLimit(
                    title: provider.rawValue,
                    remainingPercent: 50
                ),
            ]
        )
    }
}

private actor AgentUsageSequenceLoader: AgentUsageLoading {
    private(set) var loadCount = 0
    private var results: [AgentUsageSummary?]

    init(results: [AgentUsageSummary?]) {
        self.results = results
    }

    func loadSummary(for provider: AgentProvider) async -> AgentUsageSummary? {
        loadCount += 1
        return results.isEmpty ? nil : results.removeFirst()
    }
}
