import Foundation

public enum AgentSessionCostScanner {
    public static func latestCost(
        for provider: AgentProvider,
        homeDirectory: URL
    ) async -> Double? {
        await Task.detached(priority: .utility) {
            switch provider {
            case .codex:
                return latestCodexCost(homeDirectory: homeDirectory)
            case .claudeCode:
                return latestClaudeCost(homeDirectory: homeDirectory)
            case .openCode, .antigravity, .cursor:
                return nil
            }
        }.value
    }

    private static func latestCodexCost(homeDirectory: URL) -> Double? {
        let root = homeDirectory.appending(path: ".codex/sessions", directoryHint: .isDirectory)
        guard let file = recentJSONLFiles(in: root, limit: 3).first,
              let data = tailData(of: file, maximumBytes: 8 * 1_024 * 1_024)
        else { return nil }
        return AgentSessionCostCalculator.codexCost(from: data)
    }

    private static func latestClaudeCost(homeDirectory: URL) -> Double? {
        let root = homeDirectory.appending(path: ".claude/projects", directoryHint: .isDirectory)
        for file in recentJSONLFiles(in: root, limit: 12) {
            guard let data = try? Data(contentsOf: file),
                  let cost = AgentSessionCostCalculator.claudeCost(from: data)
            else { continue }
            return cost
        }
        return nil
    }

    private static func recentJSONLFiles(in root: URL, limit: Int) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }
        return files
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map(\.url)
    }

    private static func tailData(of url: URL, maximumBytes: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > maximumBytes ? end - maximumBytes : 0
        do {
            try handle.seek(toOffset: start)
            var data = try handle.readToEnd() ?? Data()
            if start > 0, let newline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(...newline)
            }
            return data
        } catch {
            return nil
        }
    }
}
