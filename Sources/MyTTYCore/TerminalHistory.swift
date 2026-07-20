import Foundation

public enum TerminalHistory {
    public static let maximumUTF8Bytes = 4 * 1_024 * 1_024
    public static let maximumBlankRun = 8

    /// Drops the empty rows the VT screen capture carries: the viewport
    /// rows below the cursor arrive as bare `\r\n`, and replaying them on
    /// restore pushed the content to the bottom of an otherwise blank
    /// screen — then the next capture persisted them, so the blank region
    /// grew with every restart. Trailing empty lines are removed entirely
    /// and interior runs are capped, keeping short intentional gaps.
    public static func sanitized(
        _ value: String,
        maximumBlankRun: Int = maximumBlankRun
    ) -> String {
        let lines = value.components(separatedBy: "\r\n")
        var result: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                continue
            }
            if blankRun > 0 {
                result.append(contentsOf: Array(
                    repeating: "",
                    count: min(blankRun, maximumBlankRun)
                ))
                blankRun = 0
            }
            result.append(line)
        }
        return result.joined(separator: "\r\n")
    }

    public static func bounded(
        _ value: String,
        maximumUTF8Bytes: Int = maximumUTF8Bytes
    ) -> String? {
        guard !value.isEmpty, maximumUTF8Bytes > 0 else { return nil }
        let bytes = Array(value.utf8)
        guard bytes.count > maximumUTF8Bytes else { return value }

        let suffix = bytes.suffix(maximumUTF8Bytes)
        guard let newline = suffix.firstIndex(of: 0x0A) else {
            return nil
        }
        let content = suffix[suffix.index(after: newline)...]
        guard !content.isEmpty else { return nil }
        return "\u{1B}[0m" + String(decoding: content, as: UTF8.self)
    }
}
