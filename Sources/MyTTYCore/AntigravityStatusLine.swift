import Foundation

/// What Antigravity's `statusLine` command receives on stdin, reduced to the
/// fields mytty shows. Antigravity (agy) runs the configured command on every
/// status refresh and pipes a JSON document describing the session: context
/// window usage and the account's quota buckets. That is the only supported
/// channel for these numbers -- the conversation database is protobuf and the
/// local language server now demands a CSRF token it never exposes.
public struct AntigravityStatusLineSnapshot: Equatable, Sendable, Codable {
    public struct QuotaBucket: Equatable, Sendable, Codable {
        public let key: String
        public let remainingFraction: Double
    }

    public let sessionID: String
    public let modelName: String?
    public let contextRemainingPercent: Double?
    public let quota: [QuotaBucket]
    public let planName: String?

    /// Parses a status-line payload. The payload is untrusted: identifiers
    /// are length-checked, percentages and fractions are clamped, and
    /// anything malformed is dropped rather than rejected wholesale.
    public static func parse(_ data: Data) -> AntigravityStatusLineSnapshot? {
        guard data.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any],
              let sessionID = AgentSessionValidation.identifier(
                  (object["session_id"] as? String)
                      ?? (object["conversation_id"] as? String)
              ),
              AntigravityStatusLineStore.isSafeFileStem(sessionID)
        else { return nil }

        let model = object["model"] as? [String: Any]
        let modelName = AgentSessionValidation.label(
            (model?["display_name"] as? String) ?? (model?["id"] as? String)
        )

        let window = object["context_window"] as? [String: Any]
        let contextRemaining: Double? = {
            if let remaining = number(window?["remaining_percentage"]) {
                return clampPercent(remaining)
            }
            if let used = number(window?["used_percentage"]) {
                return clampPercent(100 - used)
            }
            return nil
        }()

        var buckets: [QuotaBucket] = []
        if let quota = object["quota"] as? [String: Any] {
            for key in quota.keys.sorted() {
                guard let label = AgentSessionValidation.label(key),
                      let entry = quota[key] as? [String: Any],
                      let fraction = number(entry["remaining_fraction"])
                else { continue }
                buckets.append(QuotaBucket(
                    key: label,
                    remainingFraction: min(1, max(0, fraction))
                ))
            }
        }

        return AntigravityStatusLineSnapshot(
            sessionID: sessionID,
            modelName: modelName,
            contextRemainingPercent: contextRemaining,
            quota: buckets,
            planName: AgentSessionValidation.label(object["plan_tier"] as? String)
        )
    }

    /// Quota buckets folded into the same two meters the language-server
    /// path produced: one per model family, showing its tightest window.
    public var usageSummary: AgentUsageSummary? {
        var families: [(rank: Int, title: String, remaining: Double)] = []
        for bucket in quota {
            let family: (Int, String)
            if bucket.key.hasPrefix("gemini") {
                family = (0, "Gemini")
            } else if bucket.key.hasPrefix("3p") {
                family = (1, "Claude/GPT")
            } else {
                family = (2, bucket.key)
            }
            if let index = families.firstIndex(where: { $0.title == family.1 }) {
                families[index].remaining = min(
                    families[index].remaining,
                    bucket.remainingFraction
                )
            } else {
                families.append((
                    family.0,
                    family.1,
                    bucket.remainingFraction
                ))
            }
        }
        let limits = families
            .sorted {
                $0.rank != $1.rank ? $0.rank < $1.rank : $0.title < $1.title
            }
            .map {
                AgentUsageLimit(
                    title: $0.title,
                    remainingPercent: $0.remaining * 100
                )
            }
        guard !limits.isEmpty else { return nil }
        return AgentUsageSummary(cost: nil, limits: limits)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

/// Per-session snapshots written by `mytty-agent-hook antigravity-statusline`
/// and read back by the app. Lives next to the app's event socket, so a dev
/// build and an installed release (which share the global agy settings but
/// not the socket directory) each see only the panes they started.
public struct AntigravityStatusLineStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public init(socketDirectory: URL) {
        self.directory = socketDirectory
            .appendingPathComponent("agy-statusline", isDirectory: true)
    }

    static func isSafeFileStem(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value.unicodeScalars.allSatisfy {
                ($0.value < 128)
                    && (CharacterSet.alphanumerics.contains($0)
                        || $0 == "-" || $0 == "_")
            }
    }

    private func url(for sessionID: String) -> URL {
        directory.appendingPathComponent(
            sessionID + ".json",
            isDirectory: false
        )
    }

    /// Validates `payload` and stores the reduced snapshot. Returns false
    /// when the payload isn't a usable status-line document.
    @discardableResult
    public func record(payload: Data) throws -> Bool {
        guard let snapshot = AntigravityStatusLineSnapshot.parse(payload)
        else { return false }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(snapshot)
        let destination = url(for: snapshot.sessionID)
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        return true
    }

    public func snapshot(sessionID: String) -> AntigravityStatusLineSnapshot? {
        guard AntigravityStatusLineStore.isSafeFileStem(sessionID),
              let data = try? Data(contentsOf: url(for: sessionID))
        else { return nil }
        return try? JSONDecoder().decode(
            AntigravityStatusLineSnapshot.self,
            from: data
        )
    }

    /// The most recently written snapshot no older than `maxAge`. Quota is
    /// account-wide, so any live session's numbers will do.
    public func latest(
        maxAge: TimeInterval,
        now: Date = Date()
    ) -> AntigravityStatusLineSnapshot? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        let newest = entries
            .filter { $0.pathExtension == "json" }
            .compactMap { entry -> (URL, Date)? in
                guard let date = try? entry.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate,
                    now.timeIntervalSince(date) <= maxAge
                else { return nil }
                return (entry, date)
            }
            .max { $0.1 < $1.1 }
        guard let newest,
              let data = try? Data(contentsOf: newest.0)
        else { return nil }
        return try? JSONDecoder().decode(
            AntigravityStatusLineSnapshot.self,
            from: data
        )
    }
}

/// The `statusLine.command` string mytty installs into Antigravity's
/// settings, and the inverse used to find (and unwrap) it again.
public enum AntigravityStatusLineCommand {
    public static let subcommand = "antigravity-statusline"

    private static func prefix(hookExecutable: URL) -> String {
        "\(ShellQuoting.quote(hookExecutable.path)) \(subcommand)"
    }

    /// `original` is the user's own status-line command, if any; mytty runs
    /// it with the same stdin and passes its output through.
    public static func command(
        hookExecutable: URL,
        wrapping original: String?
    ) -> String {
        let base = prefix(hookExecutable: hookExecutable)
        guard let original,
              !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return base }
        return "\(base) --wrap \(ShellQuoting.quote(original))"
    }

    public enum Parsed: Equatable {
        case notOwned
        case owned(wrapped: String?)
    }

    public static func parse(
        _ command: String,
        hookExecutable: URL
    ) -> Parsed {
        let base = prefix(hookExecutable: hookExecutable)
        if command == base { return .owned(wrapped: nil) }
        let wrapPrefix = base + " --wrap "
        guard command.hasPrefix(wrapPrefix),
              let original = unquote(String(command.dropFirst(wrapPrefix.count)))
        else { return .notOwned }
        return .owned(wrapped: original)
    }

    /// Inverse of `ShellQuoting.quote`; nil for anything else.
    static func unquote(_ value: String) -> String? {
        var result = ""
        var rest = Substring(value)
        guard rest.first == "'" else { return nil }
        while !rest.isEmpty {
            guard rest.first == "'" else { return nil }
            rest = rest.dropFirst()
            guard let close = rest.firstIndex(of: "'") else { return nil }
            result += rest[rest.startIndex..<close]
            rest = rest[rest.index(after: close)...]
            if rest.isEmpty { return result }
            guard rest.hasPrefix("\\''") else { return nil }
            result += "'"
            rest = rest.dropFirst(2)
        }
        return nil
    }
}
