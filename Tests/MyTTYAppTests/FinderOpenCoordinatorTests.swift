import Foundation
import Testing

@testable import MyTTYApp

@Suite("Finder open coordination")
struct FinderOpenCoordinatorTests {
    @Test("opens a folder URL as its own working directory")
    func folderURL() {
        let folder = URL(fileURLWithPath: "/Users/demo/project", isDirectory: true)

        let resolved = FinderOpenPolicy.workingDirectory(
            for: folder,
            isDirectory: { _ in true }
        )

        #expect(resolved == folder.standardizedFileURL)
    }

    @Test("opens a file URL in its parent directory")
    func fileURL() {
        let file = URL(fileURLWithPath: "/Users/demo/project/README.md")

        let resolved = FinderOpenPolicy.workingDirectory(
            for: file,
            isDirectory: { _ in false }
        )

        #expect(
            resolved
                == URL(fileURLWithPath: "/Users/demo/project", isDirectory: true)
                    .standardizedFileURL
        )
    }

    @Test("rejects non-file URLs")
    func nonFileURL() {
        let remote = URL(string: "https://example.com/folder")!

        let resolved = FinderOpenPolicy.workingDirectory(
            for: remote,
            isDirectory: { _ in true }
        )

        #expect(resolved == nil)
    }

    @Test("rejects paths that do not exist on disk")
    func missingPath() {
        let missing = URL(fileURLWithPath: "/Users/demo/gone", isDirectory: true)

        let resolved = FinderOpenPolicy.workingDirectory(
            for: missing,
            isDirectory: { _ in nil }
        )

        #expect(resolved == nil)
    }

    @Test("standardizes relative components before opening")
    func standardizesPath() {
        let dotted = URL(
            fileURLWithPath: "/Users/demo/project/../project",
            isDirectory: true
        )

        let resolved = FinderOpenPolicy.workingDirectory(
            for: dotted,
            isDirectory: { _ in true }
        )

        #expect(resolved?.path == "/Users/demo/project")
    }

    @Test("deduplicates resolved directories while preserving order")
    func deduplicatesDirectories() {
        let folder = URL(fileURLWithPath: "/Users/demo/a", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/Users/demo/b", isDirectory: true)
        let fileInFolder = URL(fileURLWithPath: "/Users/demo/a/file.txt")

        let resolved = FinderOpenPolicy.workingDirectories(
            for: [folder, fileInFolder, sibling, folder],
            isDirectory: { $0.path.hasSuffix("file.txt") ? false : true }
        )

        #expect(
            resolved == [
                folder.standardizedFileURL,
                sibling.standardizedFileURL,
            ]
        )
    }

    @Test("holds URLs that arrive before launch finishes")
    func queueBuffersBeforeReady() {
        var queue = FinderOpenQueue()
        let folder = URL(fileURLWithPath: "/Users/demo/project", isDirectory: true)

        #expect(queue.enqueue([folder]).isEmpty)
        #expect(queue.markReady() == [folder])
    }

    @Test("passes URLs straight through once launch finished")
    func queuePassesThroughWhenReady() {
        var queue = FinderOpenQueue()
        let folder = URL(fileURLWithPath: "/Users/demo/project", isDirectory: true)

        #expect(queue.markReady().isEmpty)
        #expect(queue.enqueue([folder]) == [folder])
    }

    @Test("flushes buffered URLs only once")
    func queueFlushesOnce() {
        var queue = FinderOpenQueue()
        let folder = URL(fileURLWithPath: "/Users/demo/project", isDirectory: true)

        _ = queue.enqueue([folder])
        #expect(queue.markReady() == [folder])
        #expect(queue.markReady().isEmpty)
    }
}
