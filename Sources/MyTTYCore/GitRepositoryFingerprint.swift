import Foundation

/// A cheap, subprocess-free fingerprint of a git repository's metadata,
/// used to decide whether re-running `git` (to re-derive the GitHub page
/// URL / branch name) could possibly produce a different answer since the
/// last load. Only stats a couple of small files — it never shells out and
/// never reads file contents beyond the `.git`/`commondir` pointer files
/// themselves, which are a handful of bytes.
public enum GitRepositoryFingerprint: Equatable, Sendable {
    /// `directory` is not inside a git working tree (no `.git` found while
    /// walking up to the filesystem root). Callers should skip spawning
    /// `git` entirely rather than treat this as "unknown".
    case notARepository
    case repository(head: FileState, config: FileState)

    /// Missing files fingerprint as `.absent` — a valid, stable state of
    /// its own (e.g. a repository with no commits yet has no `HEAD`... in
    /// practice `HEAD` always exists once `.git` does, but `config` can be
    /// deleted by hand), not an error to propagate.
    public enum FileState: Equatable, Sendable {
        case absent
        case present(mtime: Date, size: UInt64)
    }

    /// Bounds the walk up from a working directory looking for `.git` —
    /// deep enough for any real checkout, shallow enough to never spin on
    /// a pathological or cyclic mount.
    private static let maximumAncestorLevels = 64
    /// `.git` files and `commondir` are one line of a filesystem path;
    /// anything past this is either not ours to parse or corrupt.
    private static let maximumPointerFileBytes = 4_096

    /// Resolves the repository's `HEAD` and `config` (following
    /// worktree/submodule `gitdir:` files and `commondir`) and fingerprints
    /// them by (mtime, size). Never throws; malformed git metadata reports
    /// as `.notARepository` rather than crashing or guessing.
    public static func compute(for directory: URL) -> GitRepositoryFingerprint {
        guard directory.isFileURL,
              let gitDir = resolveGitDir(startingAt: directory.standardizedFileURL)
        else { return .notARepository }
        let commonDir = resolveCommonDir(for: gitDir)
        return .repository(
            head: fileState(gitDir.appendingPathComponent("HEAD")),
            config: fileState(commonDir.appendingPathComponent("config"))
        )
    }

    private static func fileState(_ url: URL) -> FileState {
        guard let (mtime, size) = FileFingerprint.of(url) else { return .absent }
        return .present(mtime: mtime, size: size)
    }

    /// Walks up from `directory` looking for a `.git` entry, which may be a
    /// directory (normal clone) or a file (worktree/submodule, contents
    /// `gitdir: <path>`). Returns the resolved git directory, or `nil` if
    /// none is found, or the entry found is malformed.
    private static func resolveGitDir(startingAt directory: URL) -> URL? {
        var current = directory
        for _ in 0..<maximumAncestorLevels {
            let dotGit = current.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return dotGit.standardizedFileURL
                }
                return resolveGitFile(dotGit, in: current)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
        return nil
    }

    /// Parses a worktree/submodule `.git` file's `gitdir: <path>` line.
    /// `<path>` may be relative to `containingDirectory` (the directory the
    /// `.git` file itself lives in) or absolute.
    private static func resolveGitFile(_ fileURL: URL, in containingDirectory: URL) -> URL? {
        guard let path = pointerPath(in: fileURL, prefix: "gitdir:") else { return nil }
        return resolvedPath(path, relativeTo: containingDirectory, isDirectory: true)
    }

    /// A linked worktree's gitdir (`<main>/.git/worktrees/<name>`) holds a
    /// `commondir` file pointing at the main repository's git dir, possibly
    /// relatively — that's where `config` (as opposed to the worktree's own
    /// `HEAD`) actually lives. Falls back to `gitDir` itself when absent,
    /// which covers both normal clones and the main worktree.
    private static func resolveCommonDir(for gitDir: URL) -> URL {
        let commondirFile = gitDir.appendingPathComponent("commondir")
        guard let path = pointerPath(in: commondirFile, prefix: nil) else { return gitDir }
        return resolvedPath(path, relativeTo: gitDir, isDirectory: true)
    }

    /// Reads a small pointer file and returns its single relevant line,
    /// with `prefix` stripped if given. `nil` on any malformed input:
    /// unreadable, oversized, non-UTF8, missing prefix, or empty path.
    private static func pointerPath(in fileURL: URL, prefix: String?) -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              data.count <= maximumPointerFileBytes,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            var value = line.trimmingCharacters(in: .whitespaces)
            if let prefix {
                guard value.hasPrefix(prefix) else { continue }
                value.removeFirst(prefix.count)
                value = value.trimmingCharacters(in: .whitespaces)
            }
            guard !value.isEmpty else { return nil }
            return value
        }
        return nil
    }

    private static func resolvedPath(
        _ path: String,
        relativeTo directory: URL,
        isDirectory: Bool
    ) -> URL {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: isDirectory)
            : directory.appendingPathComponent(path, isDirectory: isDirectory)
        return url.standardizedFileURL
    }
}
