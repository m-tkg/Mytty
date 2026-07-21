import Foundation

/// Language for the one-liner composer's sentence replies. MyTTYCore only
/// ever sees an already-resolved language; the app converts from
/// `ResolvedAppLanguage` (same pattern as `PaneTeamPointerLanguage`).
public enum OneLinerLanguage: Equatable, Sendable {
    case english
    case japanese
}

/// Prompt construction and output cleanup for the on-device one-liner
/// composer. Lives in MyTTYCore so the `mytty-oneliner-eval` harness can
/// evaluate the exact production prompt; the Foundation Models call stays
/// in MyTTYApp (`OneLinerComposer`).
public enum OneLinerPrompt {
    /// The on-device model is small, so the instructions carry explicit
    /// decision rules and few-shot examples for the failure clusters the
    /// eval surfaced: file contents vs file names, named-file operations
    /// (wc/head/tail on one file, not find pipelines), literal search
    /// strings, "matches X but not Y" via grep -v, and BSD-vs-GNU flags.
    /// This wording scores 18/25 on `swift run mytty-oneliner-eval`.
    /// The example count is at the model's capacity: a ninth example
    /// collapsed the score to 13/25, and even reordering or rephrasing
    /// rules reshuffles which cases pass — never edit this prompt
    /// without re-running the eval.
    public static func instructions(language: OneLinerLanguage) -> String {
        let languageLine =
            switch language {
            case .english:
                "If you reply with a sentence, write it in English."
            case .japanese:
                "If you reply with a sentence, write it in Japanese."
            }
        return """
        You write shell one-liners for macOS (zsh). Reply with exactly \
        one command line and nothing else — no explanation, no code \
        fences, no leading $.

        Decision rules — read the task carefully:
        - If the task names one specific file, run the command on that \
        file directly (wc -l, head, tail, sort, grep FILE). Do NOT use \
        find or recursive grep for a named file.
        - Searching file CONTENTS across files (中身, 内容, ファイル内, \
        含まれている文字列): use grep recursively. NEVER use find -name \
        for contents.
        - Searching file NAMES (ファイル名): use find -name.
        - Always single-quote search patterns. Search strings from the \
        task are literal text — copy them exactly, never invent \
        character classes.
        - Only when the task EXCLUDES something (〜は含まない, \
        〜を除く, "but not"), add one grep -v with the excluded string. \
        Otherwise never use grep -v.
        - This is macOS: BSD tools only (stat -f, du -sh); no GNU-only \
        flags like stat -c.
        - Useful find predicates: -mtime -N (N日以内に更新), \
        -size +1M (1MB より大きい), -empty (空のファイル), \
        -name '.*' (隠しファイル).

        Examples:
        Task: ファイル名に log を含むファイルを探す
        Reply: find . -type f -name '*log*'
        Task: .txt で終わるファイル名のファイルを探す
        Reply: find . -type f -name '*.txt'
        Task: ファイルの中に TODO と書かれているファイルを探す
        Reply: find . -type f -print0 | xargs -0 grep -l 'TODO'
        Task: 3日以内に更新されたファイルを探す
        Reply: find . -type f -mtime -3
        Task: list files larger than 100MB
        Reply: find . -type f -size +100M
        Task: foo で始まるが foobar は含まない行を検索
        Reply: grep -r '^foo' . | grep -v 'foobar'
        Task: data.txt の行数を数える
        Reply: wc -l < data.txt
        Task: data.txt の最後の5行を表示
        Reply: tail -5 data.txt

        Almost every task has a one-line answer built from find, grep, \
        and the standard tools — when a decision rule or example \
        matches, always answer with a command. Only if the task truly \
        cannot be done in a single command line, reply instead with one \
        short sentence saying that it cannot and why. \(languageLine)
        """
    }

    public static func prompt(request: String) -> String {
        """
        Task: \(request.trimmingCharacters(in: .whitespacesAndNewlines))
        Reply:
        """
    }

    /// Reduces a model response to one usable line. Model output is
    /// untrusted: strip code fences, wrapping backticks, shell-prompt
    /// prefixes, and control characters.
    public static func sanitize(_ raw: String) -> String? {
        var lines = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        guard var line = lines.first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return nil }
        line.removeAll { $0.isASCII && ($0.asciiValue ?? 0) < 0x20 }
        line = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["Reply:", "$ ", "% "] where line.hasPrefix(prefix) {
            line = String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
        }
        while line.count >= 2, line.hasPrefix("`"), line.hasSuffix("`") {
            line = String(line.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        line = line.trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }
}
