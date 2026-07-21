import Foundation

/// How a generated command's behavior is judged. Every case runs in a
/// fresh fixture tree; judging inspects stdout (and for mutations, the
/// tree) rather than string-matching the command, because "looks
/// different but behaves the same" must pass and "looks right but
/// behaves subtly wrong" must fail — the failure class the eval exists
/// to catch.
enum Expectation {
    /// Output is exactly this set of fixture-relative paths.
    case paths(Set<String>)
    /// Output lines, after stripping any `path:` / `path:line:` grep
    /// prefix, equal this multiset.
    case contentLines([String])
    /// Output lines in exactly this order.
    case orderedLines([String])
    /// The first integer in the output equals this value.
    case count(Int)
    /// Output has no duplicate lines and, after prefix stripping,
    /// equals this set.
    case uniqueSet(Set<String>)
    /// A file was created with this exact content.
    case fileCreated(path: String, content: String)
    /// Free-form predicate on (stdout, fixture root).
    case custom(String, @Sendable (String, URL) -> Bool)
}

struct EvalCase {
    let id: String
    let task: String
    /// Human-written reference solution, shown next to failures.
    let reference: String
    let expectation: Expectation
}

enum EvalFixture {
    static let appLog = """
    error: disk full
    error_log rotated
    warning: low memory
    warn: minor
    info: ok
    error: disk full
    abc start
    abcd start
    """

    static let samples = """
    abc alpha
    abcd beta
    abc gamma abcd
    xyz
    """

    static let readme = "hello\nTODO later\n"
    static let mainSwift = "class A {\n  deinit {}\n}\n// TODO: cleanup\n"
    static let utilPy = "import os\nimport sys\nimport json\n"
    static let notes = "notes line1\nline2\n"

    /// Builds the tree under `root`. Files marked old get a 30-day-old
    /// mtime so `-mtime -7` style tasks have both sides of the boundary.
    static func build(at root: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        func write(_ path: String, _ content: String, old: Bool = false) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.data(using: .utf8)!.write(to: url)
            if old {
                try fm.setAttributes(
                    [.modificationDate: Date(timeIntervalSinceNow: -30 * 86400)],
                    ofItemAtPath: url.path
                )
            }
        }
        try write("readme.txt", readme)
        try write("notes.md", notes, old: true)
        try write("app.log", appLog + "\n")
        try write("build.log", "ok\n", old: true)
        try write("logbook.txt", "entries\n", old: true)
        try write("samples.txt", samples + "\n")
        try write("empty.txt", "")
        try write(".hidden", "secret\n", old: true)
        try write("my file.txt", "spaced\n")
        try write("src/main.swift", mainSwift)
        try write("src/util.py", utilPy)
        try write("logs/old.log", "archived\n", old: true)
        let big = root.appendingPathComponent("data/big.bin")
        try fm.createDirectory(
            at: big.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: 2 * 1024 * 1024).write(to: big)
        try Data(count: 10).write(
            to: root.appendingPathComponent("data/small.bin")
        )
    }

    /// Every regular file that gets a fresh (now) mtime above.
    static let recentFiles: Set<String> = [
        "readme.txt", "app.log", "samples.txt", "empty.txt",
        "my file.txt", "src/main.swift", "src/util.py",
        "data/big.bin", "data/small.bin",
    ]
}

let evalCases: [EvalCase] = [
    EvalCase(
        id: "mtime-recent",
        task: "7日以内に更新されたファイルを探す",
        reference: "find . -type f -mtime -7",
        expectation: .paths(EvalFixture.recentFiles)
    ),
    EvalCase(
        id: "name-contains",
        task: "ファイル名に log を含むファイルを探す",
        reference: "find . -type f -name '*log*'",
        expectation: .paths(
            ["app.log", "build.log", "logbook.txt", "logs/old.log"]
        )
    ),
    EvalCase(
        id: "name-suffix",
        task: ".log で終わるファイル名のファイルを探す",
        reference: "find . -type f -name '*.log'",
        expectation: .paths(["app.log", "build.log", "logs/old.log"])
    ),
    EvalCase(
        id: "contents-todo",
        task: "ファイルの中に TODO と書かれているファイルを探す",
        reference: "find . -type f -print0 | xargs -0 grep -l 'TODO'",
        expectation: .paths(["readme.txt", "src/main.swift"])
    ),
    EvalCase(
        id: "prefix-not-contains",
        task: #"grep で、"abcで始まる"けど"abcdは含まない"、という文字列の検索"#,
        reference: "grep -r '^abc' . | grep -v 'abcd'",
        expectation: .contentLines(["abc alpha", "abc start"])
    ),
    EvalCase(
        id: "contains-not-contains",
        task: "error を含むが error_log は含まない行を探す",
        reference: "grep -r 'error' . | grep -v 'error_log'",
        expectation: .contentLines(["error: disk full", "error: disk full"])
    ),
    EvalCase(
        id: "empty-files",
        task: "空のファイルを探す",
        reference: "find . -type f -empty",
        expectation: .paths(["empty.txt"])
    ),
    EvalCase(
        id: "size-over-1m",
        task: "1MB より大きいファイルを探す",
        reference: "find . -type f -size +1M",
        expectation: .paths(["data/big.bin"])
    ),
    EvalCase(
        id: "size-over-100m",
        task: "list files larger than 100MB",
        reference: "find . -type f -size +100M",
        expectation: .paths([])
    ),
    EvalCase(
        id: "line-count",
        task: "app.log の行数を数える",
        reference: "wc -l < app.log",
        expectation: .count(8)
    ),
    EvalCase(
        id: "match-count",
        task: "app.log の中で warning を含む行数を数える",
        reference: "grep -c 'warning' app.log",
        expectation: .count(1)
    ),
    EvalCase(
        id: "hidden-files",
        task: "隠しファイルを探す",
        reference: "find . -type f -name '.*'",
        expectation: .paths([".hidden"])
    ),
    EvalCase(
        id: "ext-scoped-grep",
        task: "サブディレクトリも含めて拡張子 .swift のファイルの中から deinit を検索",
        reference: "grep -r --include='*.swift' 'deinit' .",
        expectation: .custom("mentions src/main.swift or its deinit line") {
            stdout, _ in
            let lines = stdout.split(separator: "\n").map(String.init)
            guard !lines.isEmpty else { return false }
            return lines.allSatisfy {
                $0.contains("main.swift") || $0.contains("deinit")
            } && lines.contains { $0.contains("deinit") || $0.contains("main.swift") }
        }
    ),
    EvalCase(
        id: "first-line",
        task: "notes.md の1行目を表示",
        reference: "head -1 notes.md",
        expectation: .orderedLines(["notes line1"])
    ),
    EvalCase(
        id: "last-two-lines",
        task: "app.log の最後の2行を表示",
        reference: "tail -2 app.log",
        expectation: .orderedLines(["abc start", "abcd start"])
    ),
    EvalCase(
        id: "dedupe-lines",
        task: "app.log の重複行を除いて表示",
        reference: "sort app.log | uniq",
        expectation: .uniqueSet([
            "error: disk full", "error_log rotated", "warning: low memory",
            "warn: minor", "info: ok", "abc start", "abcd start",
        ])
    ),
    EvalCase(
        id: "space-in-name",
        task: "ファイル名にスペースを含むファイルを探す",
        reference: "find . -type f -name '* *'",
        expectation: .paths(["my file.txt"])
    ),
    EvalCase(
        id: "list-subdirs",
        task: "カレントディレクトリ直下のサブディレクトリを一覧",
        reference: "find . -maxdepth 1 -type d -not -name '.'",
        expectation: .custom("exactly data, logs, src") { stdout, _ in
            let tokens = stdout
                .split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" })
                .map {
                    var t = String($0)
                    if t.hasPrefix("./") { t.removeFirst(2) }
                    if t.hasSuffix("/") { t.removeLast() }
                    return t
                }
                .filter { !$0.isEmpty && $0 != "." }
            return Set(tokens) == ["data", "logs", "src"]
                && tokens.count == 3
        }
    ),
    EvalCase(
        id: "import-not-os",
        task: "lines starting with import but not import os",
        reference: "grep -r '^import' . | grep -v 'import os'",
        expectation: .contentLines(["import sys", "import json"])
    ),
    EvalCase(
        id: "largest-file",
        task: "一番サイズが大きいファイルを表示",
        reference: "find . -type f -exec du -k {} + | sort -rn | head -1",
        expectation: .custom("names data/big.bin") { stdout, _ in
            !stdout.isEmpty && stdout.contains("big.bin")
        }
    ),
    EvalCase(
        id: "count-by-ext",
        task: "拡張子 .py のファイルの数を数える",
        reference: "find . -type f -name '*.py' | wc -l",
        expectation: .count(1)
    ),
    EvalCase(
        id: "copy-file",
        task: "readme.txt を backup.txt という名前でコピー",
        reference: "cp readme.txt backup.txt",
        expectation: .fileCreated(
            path: "backup.txt", content: EvalFixture.readme
        )
    ),
    EvalCase(
        id: "disk-usage",
        task: "カレントディレクトリ全体のディスク使用量を表示",
        reference: "du -sh .",
        expectation: .custom("a single total for '.'") { stdout, _ in
            let lines = stdout.split(separator: "\n")
            guard lines.count == 1, let line = lines.first else {
                return false
            }
            return line.hasSuffix(".") || line.hasSuffix("./")
        }
    ),
    EvalCase(
        id: "total-occurrences",
        task: "TODO という文字列がファイル内に出てくる回数を合計する",
        reference: "grep -ro 'TODO' . | wc -l",
        expectation: .count(2)
    ),
    EvalCase(
        id: "ext-scoped-grep-2",
        task: ".log ファイルの中から archived を検索",
        reference: "grep -r --include='*.log' 'archived' .",
        expectation: .custom("finds logs/old.log's archived line") {
            stdout, _ in
            let lines = stdout.split(separator: "\n").map(String.init)
            guard !lines.isEmpty else { return false }
            return lines.allSatisfy {
                $0.contains("archived") || $0.contains("old.log")
            }
        }
    ),
]
