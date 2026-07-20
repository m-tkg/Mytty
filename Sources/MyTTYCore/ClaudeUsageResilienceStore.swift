import Foundation

public actor ClaudeUsageResilienceStore {
    public static let shared = ClaudeUsageResilienceStore()

    private struct Record: Codable, Sendable {
        var savedAt: Date
        var limits: [AgentUsageLimit]
        var blockedUntil: Date?
    }

    private let defaultCooldown: TimeInterval
    private let staleLifetime: TimeInterval
    private var records: [URL: Record] = [:]
    private var loadedURLs: Set<URL> = []
    private var requestsInFlight: Set<URL> = []

    public init(
        defaultCooldown: TimeInterval = 5 * 60,
        staleLifetime: TimeInterval = 24 * 60 * 60
    ) {
        self.defaultCooldown = max(0, defaultCooldown)
        self.staleLifetime = max(0, staleLifetime)
    }

    public func beginRequest(cacheURL: URL, now: Date = Date()) -> Bool {
        guard !requestsInFlight.contains(cacheURL) else { return false }
        if let blockedUntil = record(for: cacheURL)?.blockedUntil,
           blockedUntil > now {
            return false
        }
        requestsInFlight.insert(cacheURL)
        return true
    }

    public func recordLimits(
        _ limits: [AgentUsageLimit],
        cacheURL: URL,
        now: Date = Date()
    ) {
        requestsInFlight.remove(cacheURL)
        let record = Record(
            savedAt: now,
            limits: limits,
            blockedUntil: nil
        )
        records[cacheURL] = record
        loadedURLs.insert(cacheURL)
        persist(record, to: cacheURL)
    }

    public func recordRateLimit(
        retryAfter: Date?,
        cacheURL: URL,
        now: Date = Date()
    ) {
        requestsInFlight.remove(cacheURL)
        var record = record(for: cacheURL) ?? Record(
            savedAt: .distantPast,
            limits: [],
            blockedUntil: nil
        )
        let candidate = if let retryAfter, retryAfter > now {
            retryAfter
        } else {
            now.addingTimeInterval(defaultCooldown)
        }
        record.blockedUntil = max(record.blockedUntil ?? candidate, candidate)
        records[cacheURL] = record
        loadedURLs.insert(cacheURL)
        persist(record, to: cacheURL)
    }

    public func recordFailure(cacheURL: URL) {
        requestsInFlight.remove(cacheURL)
    }

    public func cachedLimits(
        cacheURL: URL,
        now: Date = Date()
    ) -> [AgentUsageLimit] {
        guard let record = record(for: cacheURL),
              now >= record.savedAt,
              now.timeIntervalSince(record.savedAt) <= staleLifetime
        else { return [] }
        return record.limits
    }

    private func record(for url: URL) -> Record? {
        if loadedURLs.contains(url) {
            return records[url]
        }
        loadedURLs.insert(url)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return nil }
        records[url] = record
        return record
    }

    private func persist(_ record: Record, to url: URL) {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            return
        }
    }
}
