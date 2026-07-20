import Foundation
import Testing

@testable import MyTTYCore

@Suite("GitHub repository status")
struct GitHubRepositoryTests {
    @Test(
        "normalizes supported GitHub remote formats",
        arguments: [
            "https://github.com/m-tkg/Mytty.git",
            "http://github.com/m-tkg/Mytty",
            "git@github.com:m-tkg/Mytty.git",
            "ssh://git@github.com/m-tkg/Mytty.git",
            "git://github.com/m-tkg/Mytty.git",
        ]
    )
    func supportedRemote(remote: String) {
        #expect(
            GitHubRemoteURL.pageURL(from: remote)?.absoluteString
                == "https://github.com/m-tkg/Mytty"
        )
    }

    @Test(
        "rejects non-GitHub and ambiguous remote URLs",
        arguments: [
            "https://github.com.evil.example/m-tkg/Mytty.git",
            "git@gitlab.com:m-tkg/Mytty.git",
            "https://github.com/m-tkg",
            "https://github.com/m-tkg/Mytty/extra",
            "not a remote",
        ]
    )
    func unsupportedRemote(remote: String) {
        #expect(GitHubRemoteURL.pageURL(from: remote) == nil)
    }

    @Test("loads the branch and prioritizes a GitHub origin remote")
    func repositoryStatus() async {
        let directory = URL(fileURLWithPath: "/repo", isDirectory: true)
        let runner = StubGitCommandRunner(outputs: [
            ["branch", "--show-current"]: "feature/status\n",
            ["remote"]: "upstream\norigin\n",
            ["remote", "get-url", "origin"]:
                "git@github.com:m-tkg/Mytty.git\n",
        ])
        let loader = GitHubRepositoryLoader(runner: runner)

        let status = await loader.load(from: directory)

        #expect(status == GitHubRepositoryStatus(
            pageURL: URL(string: "https://github.com/m-tkg/Mytty")!,
            branchName: "feature/status"
        ))
    }

    @Test("uses a short commit when HEAD is detached")
    func detachedHead() async {
        let runner = StubGitCommandRunner(outputs: [
            ["branch", "--show-current"]: "\n",
            ["rev-parse", "--short", "HEAD"]: "a1b2c3d\n",
            ["remote"]: "origin\n",
            ["remote", "get-url", "origin"]:
                "https://github.com/m-tkg/Mytty.git\n",
        ])
        let loader = GitHubRepositoryLoader(runner: runner)

        let status = await loader.load(
            from: URL(fileURLWithPath: "/repo", isDirectory: true)
        )

        #expect(status?.branchName == "a1b2c3d")
    }

    @Test("reads the branch after remote discovery to publish fresh status")
    func freshBranchSnapshot() async {
        let runner = RecordingGitCommandRunner(outputs: [
            ["remote"]: "origin\n",
            ["remote", "get-url", "origin"]:
                "https://github.com/m-tkg/Mytty.git\n",
            ["branch", "--show-current"]: "feature/latest\n",
        ])
        let loader = GitHubRepositoryLoader(runner: runner)

        let status = await loader.load(
            from: URL(fileURLWithPath: "/repo", isDirectory: true)
        )

        #expect(status?.branchName == "feature/latest")
        #expect(await runner.calls() == [
            ["remote"],
            ["remote", "get-url", "origin"],
            ["branch", "--show-current"],
        ])
    }
}

private struct StubGitCommandRunner: GitCommandRunning {
    let outputs: [[String]: String]

    func output(in directory: URL, arguments: [String]) async -> String? {
        outputs[arguments]
    }
}

private actor RecordingGitCommandRunner: GitCommandRunning {
    let outputs: [[String]: String]
    private var recordedCalls: [[String]] = []

    init(outputs: [[String]: String]) {
        self.outputs = outputs
    }

    func output(in directory: URL, arguments: [String]) async -> String? {
        recordedCalls.append(arguments)
        return outputs[arguments]
    }

    func calls() -> [[String]] {
        recordedCalls
    }
}
