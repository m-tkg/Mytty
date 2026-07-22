import Foundation
import Testing

@testable import MyTTYCore

@Suite("Git repository fingerprint")
struct GitRepositoryFingerprintTests {
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func state(of url: URL) -> GitRepositoryFingerprint.FileState {
        guard let (mtime, size) = FileFingerprint.of(url) else { return .absent }
        return .present(mtime: mtime, size: size)
    }

    @Test("fingerprints HEAD and config of a normal .git directory")
    func normalGitDirectory() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gitDir = root.appendingPathComponent(".git", isDirectory: true)
        try write("ref: refs/heads/main\n", to: gitDir.appendingPathComponent("HEAD"))
        try write(
            "[core]\n\trepositoryformatversion = 0\n",
            to: gitDir.appendingPathComponent("config")
        )

        let fingerprint = GitRepositoryFingerprint.compute(for: root)

        #expect(fingerprint == .repository(
            head: state(of: gitDir.appendingPathComponent("HEAD")),
            config: state(of: gitDir.appendingPathComponent("config"))
        ))
        guard case .repository(let head, let config) = fingerprint else {
            Issue.record("expected .repository")
            return
        }
        #expect(head != .absent)
        #expect(config != .absent)
    }

    @Test("walks up from a nested working directory to find .git")
    func nestedWorkingDirectory() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gitDir = root.appendingPathComponent(".git", isDirectory: true)
        try write("ref: refs/heads/main\n", to: gitDir.appendingPathComponent("HEAD"))
        let nested = root.appendingPathComponent("src/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let fingerprint = GitRepositoryFingerprint.compute(for: nested)

        guard case .repository(let head, _) = fingerprint else {
            Issue.record("expected .repository")
            return
        }
        #expect(head == state(of: gitDir.appendingPathComponent("HEAD")))
    }

    @Test(".git file with an absolute gitdir resolves to the real git directory")
    func gitFileAbsoluteGitDir() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        let realGitDir = root.appendingPathComponent(
            "main/.git/worktrees/worktree",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try write("ref: refs/heads/feature\n", to: realGitDir.appendingPathComponent("HEAD"))
        try write("gitdir: \(realGitDir.path)\n", to: worktree.appendingPathComponent(".git"))

        let fingerprint = GitRepositoryFingerprint.compute(for: worktree)

        guard case .repository(let head, _) = fingerprint else {
            Issue.record("expected .repository")
            return
        }
        #expect(head == state(of: realGitDir.appendingPathComponent("HEAD")))
        #expect(head != .absent)
    }

    @Test(".git file with a relative gitdir resolves relative to its own directory")
    func gitFileRelativeGitDir() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        let realGitDir = root.appendingPathComponent(
            "main/.git/worktrees/worktree",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try write("ref: refs/heads/feature\n", to: realGitDir.appendingPathComponent("HEAD"))
        try write(
            "gitdir: ../main/.git/worktrees/worktree\n",
            to: worktree.appendingPathComponent(".git")
        )

        let fingerprint = GitRepositoryFingerprint.compute(for: worktree)

        guard case .repository(let head, _) = fingerprint else {
            Issue.record("expected .repository")
            return
        }
        #expect(head == state(of: realGitDir.appendingPathComponent("HEAD")))
        #expect(head != .absent)
    }

    @Test("resolves config via a relative commondir file, distinct from the worktree's own HEAD")
    func commondirResolution() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let commonGitDir = root.appendingPathComponent("main/.git", isDirectory: true)
        let worktreeGitDir = commonGitDir.appendingPathComponent(
            "worktrees/feature",
            isDirectory: true
        )
        let worktree = root.appendingPathComponent("feature-worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try write("ref: refs/heads/feature\n", to: worktreeGitDir.appendingPathComponent("HEAD"))
        try write(
            "[core]\n\trepositoryformatversion = 0\n",
            to: commonGitDir.appendingPathComponent("config")
        )
        try write("../..\n", to: worktreeGitDir.appendingPathComponent("commondir"))
        try write("gitdir: \(worktreeGitDir.path)\n", to: worktree.appendingPathComponent(".git"))

        let fingerprint = GitRepositoryFingerprint.compute(for: worktree)

        guard case .repository(let head, let config) = fingerprint else {
            Issue.record("expected .repository")
            return
        }
        #expect(head == state(of: worktreeGitDir.appendingPathComponent("HEAD")))
        #expect(config == state(of: commonGitDir.appendingPathComponent("config")))
        #expect(config != .absent)
    }

    @Test("malformed .git file reports not-a-repository rather than crashing")
    func malformedGitFile() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("this is not a valid git file\n", to: root.appendingPathComponent(".git"))

        #expect(GitRepositoryFingerprint.compute(for: root) == .notARepository)
    }

    @Test("empty .git file reports not-a-repository rather than crashing")
    func emptyGitFile() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("", to: root.appendingPathComponent(".git"))

        #expect(GitRepositoryFingerprint.compute(for: root) == .notARepository)
    }

    @Test("missing HEAD fingerprints as absent, not an error")
    func missingHead() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gitDir = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try write("[core]\n", to: gitDir.appendingPathComponent("config"))

        let fingerprint = GitRepositoryFingerprint.compute(for: root)

        #expect(fingerprint == .repository(
            head: .absent,
            config: state(of: gitDir.appendingPathComponent("config"))
        ))
    }

    @Test("a directory outside any git working tree reports not-a-repository")
    func nonRepository() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(GitRepositoryFingerprint.compute(for: root) == .notARepository)
    }

    @Test("fingerprint changes when HEAD is rewritten")
    func fingerprintChangesOnHeadRewrite() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let headURL = root.appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("HEAD")
        try write("ref: refs/heads/main\n", to: headURL)

        let before = GitRepositoryFingerprint.compute(for: root)
        // A branch switch or new commit changes HEAD's contents; a longer
        // ref name here also changes its size, so the assertion below
        // doesn't depend on filesystem mtime resolution.
        try write("ref: refs/heads/main-with-a-longer-name\n", to: headURL)
        let after = GitRepositoryFingerprint.compute(for: root)

        #expect(before != after)
    }
}
