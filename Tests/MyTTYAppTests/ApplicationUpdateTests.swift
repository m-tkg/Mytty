import Foundation
import Testing

@testable import MyTTYApp

@Suite("Application updates")
struct ApplicationUpdateTests {
    @Test("compares semantic release versions numerically")
    func semanticVersions() throws {
        let current = try #require(ApplicationVersion("0.1.9"))
        let patch = try #require(ApplicationVersion("v0.1.10"))
        let minor = try #require(ApplicationVersion("0.2.0"))

        #expect(patch > current)
        #expect(minor > patch)
        #expect(ApplicationVersion("release-1") == nil)
    }

    @Test("orders pre-releases below the release they lead up to")
    func prereleaseVersions() throws {
        let release = try #require(ApplicationVersion("0.2.0"))
        let beta1 = try #require(ApplicationVersion("v0.2.0-beta.1"))
        let beta2 = try #require(ApplicationVersion("0.2.0-beta.2"))
        let beta10 = try #require(ApplicationVersion("0.2.0-beta.10"))
        let priorRelease = try #require(ApplicationVersion("0.1.9"))

        #expect(beta1 < release)
        #expect(beta1 < beta2)
        #expect(beta2 < beta10)
        #expect(priorRelease < beta1)
        #expect(beta1.isPrerelease)
        #expect(!release.isPrerelease)
        #expect(beta1.description == "0.2.0-beta.1")
        #expect(ApplicationVersion("0.2.0-") == nil)
        #expect(ApplicationVersion("0.2.0-beta..1") == nil)
    }

    @Test("accepts only the signed Mytty release asset contract")
    func releaseDescriptor() throws {
        let digest = String(repeating: "a", count: 64)
        let data = Data(
            """
            {
              "tag_name": "v0.1.1",
              "html_url": "https://github.com/m-tkg/Mytty/releases/tag/v0.1.1",
              "draft": false,
              "prerelease": false,
              "assets": [{
                "name": "Mytty.zip",
                "browser_download_url": "https://github.com/m-tkg/Mytty/releases/download/v0.1.1/Mytty.zip",
                "size": 8484621,
                "digest": "sha256:\(digest)"
              }]
            }
            """.utf8
        )

        let release = try GitHubReleaseParser.release(from: data)

        #expect(release.version == ApplicationVersion("0.1.1"))
        #expect(release.tagName == "v0.1.1")
        #expect(release.asset.name == "Mytty.zip")
        #expect(release.asset.size == 8_484_621)
        #expect(release.asset.sha256 == digest)
    }

    @Test("excludes pre-releases unless explicitly included")
    func prereleaseExclusion() throws {
        let digest = String(repeating: "c", count: 64)
        let data = Data(
            """
            {
              "tag_name": "v0.2.0-beta.1",
              "html_url": "https://github.com/m-tkg/Mytty/releases/tag/v0.2.0-beta.1",
              "draft": false,
              "prerelease": true,
              "assets": [{
                "name": "Mytty.zip",
                "browser_download_url": "https://github.com/m-tkg/Mytty/releases/download/v0.2.0-beta.1/Mytty.zip",
                "size": 1024,
                "digest": "sha256:\(digest)"
              }]
            }
            """.utf8
        )

        #expect(throws: ApplicationUpdateError.invalidRelease) {
            try GitHubReleaseParser.release(from: data)
        }

        let release = try GitHubReleaseParser.release(
            from: data,
            includePrereleases: true
        )
        #expect(release.version == ApplicationVersion("0.2.0-beta.1"))
        #expect(release.version.isPrerelease)
    }

    @Test("picks the newest trustworthy entry from a release listing")
    func newestFromListing() throws {
        let digest = String(repeating: "d", count: 64)
        func entry(tag: String, prerelease: Bool) -> String {
            """
            {
              "tag_name": "\(tag)",
              "html_url": "https://github.com/m-tkg/Mytty/releases/tag/\(tag)",
              "draft": false,
              "prerelease": \(prerelease),
              "assets": [{
                "name": "Mytty.zip",
                "browser_download_url": "https://github.com/m-tkg/Mytty/releases/download/\(tag)/Mytty.zip",
                "size": 1024,
                "digest": "sha256:\(digest)"
              }]
            }
            """
        }
        let listing = Data(
            """
            [
              \(entry(tag: "v0.2.0-beta.1", prerelease: true)),
              \(entry(tag: "v0.1.9", prerelease: false))
            ]
            """.utf8
        )

        #expect(
            try GitHubReleaseParser.newestRelease(
                fromList: listing,
                includePrereleases: true
            ).version == ApplicationVersion("0.2.0-beta.1")
        )
        #expect(
            try GitHubReleaseParser.newestRelease(
                fromList: listing,
                includePrereleases: false
            ).version == ApplicationVersion("0.1.9")
        )
    }

    @Test("rejects release assets outside the trusted repository")
    func rejectsUntrustedReleaseAsset() {
        let digest = String(repeating: "b", count: 64)
        let data = Data(
            """
            {
              "tag_name": "v0.1.1",
              "html_url": "https://github.com/m-tkg/Mytty/releases/tag/v0.1.1",
              "draft": false,
              "prerelease": false,
              "assets": [{
                "name": "Mytty.zip",
                "browser_download_url": "https://example.com/Mytty.zip",
                "size": 1024,
                "digest": "sha256:\(digest)"
              }]
            }
            """.utf8
        )

        #expect(throws: ApplicationUpdateError.invalidRelease) {
            try GitHubReleaseParser.release(from: data)
        }
    }

    @Test("calculates the release archive SHA-256")
    func archiveDigest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let archive = directory.appendingPathComponent("Mytty.zip")
        try Data("Mytty update fixture".utf8).write(to: archive)

        #expect(
            try ApplicationUpdateDigest.sha256Hex(of: archive)
                == "593a6f9c9cf86780ea283511a6ffedb793d7b815e9b98e3c7a722d0a76af9245"
        )
    }

    @Test("replaces an application bundle without losing its path")
    func applicationReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent(
            "Applications/Mytty.app",
            isDirectory: true
        )
        let candidate = root.appendingPathComponent(
            "Download/Mytty.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: installed,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: candidate,
            withIntermediateDirectories: true
        )
        try Data("old".utf8).write(
            to: installed.appendingPathComponent("version")
        )
        try Data("new".utf8).write(
            to: candidate.appendingPathComponent("version")
        )

        try ApplicationBundleReplacer().replaceApplication(
            at: installed,
            with: candidate
        )

        #expect(installed.lastPathComponent == "Mytty.app")
        #expect(
            try String(
                contentsOf: installed.appendingPathComponent("version"),
                encoding: .utf8
            ) == "new"
        )
    }

    @Test("passes the pre-release preference through to the checker")
    @MainActor
    func prereleaseCheckPreference() async throws {
        let release = makeRelease(version: "0.2.0-beta.1")
        let checker = RecordingUpdateChecker(release: release)
        let model = ApplicationUpdateModel(
            currentVersion: try #require(ApplicationVersion("0.1.0")),
            checker: checker,
            installer: RecordingUpdateInstaller(),
            confirmsInstallation: { true },
            onInstalled: {}
        )

        await model.checkForUpdates()
        await model.checkForUpdates(includePrereleases: true)

        #expect(
            await checker.receivedIncludePrereleases == [false, true]
        )
        #expect(model.phase == .available(release))
        #expect(model.canUpdate)
    }

    @Test("checks, installs, and publishes update state")
    @MainActor
    func updateState() async throws {
        let release = makeRelease(version: "0.1.1")
        let installer = RecordingUpdateInstaller()
        var didInstall = false
        let model = ApplicationUpdateModel(
            currentVersion: try #require(ApplicationVersion("0.1.0")),
            checker: StubUpdateChecker(release: release),
            installer: installer,
            confirmsInstallation: { true },
            onInstalled: { didInstall = true }
        )

        await model.checkForUpdates()

        #expect(model.phase == .available(release))
        #expect(model.canUpdate)

        await model.installAvailableUpdate()

        #expect(await installer.installedReleases() == [release])
        #expect(model.phase == .installed(release.version))
        #expect(didInstall)
    }

    @Test("checks on launch and About but offers installation only on launch")
    @MainActor
    func automaticChecks() async throws {
        let release = makeRelease(version: "0.1.1")
        let launchInstaller = RecordingUpdateInstaller()
        var launchConfirmations = 0
        let launchModel = ApplicationUpdateModel(
            currentVersion: try #require(ApplicationVersion("0.1.0")),
            checker: StubUpdateChecker(release: release),
            installer: launchInstaller,
            confirmsInstallation: {
                launchConfirmations += 1
                return true
            },
            onInstalled: {}
        )

        await ApplicationUpdateAutomation(model: launchModel).check(
            trigger: .launch
        )

        #expect(launchConfirmations == 1)
        #expect(await launchInstaller.installedReleases() == [release])

        let aboutInstaller = RecordingUpdateInstaller()
        var aboutConfirmations = 0
        let aboutModel = ApplicationUpdateModel(
            currentVersion: try #require(ApplicationVersion("0.1.0")),
            checker: StubUpdateChecker(release: release),
            installer: aboutInstaller,
            confirmsInstallation: {
                aboutConfirmations += 1
                return true
            },
            onInstalled: {}
        )

        await ApplicationUpdateAutomation(model: aboutModel).check(
            trigger: .about
        )

        #expect(aboutConfirmations == 0)
        #expect(await aboutInstaller.installedReleases().isEmpty)
        #expect(aboutModel.phase == .available(release))
    }

    private func makeRelease(version: String) -> ApplicationUpdateRelease {
        let version = ApplicationVersion(version)!
        return ApplicationUpdateRelease(
            version: version,
            tagName: "v\(version)",
            pageURL: URL(
                string: "https://github.com/m-tkg/Mytty/releases/tag/v\(version)"
            )!,
            asset: ApplicationUpdateAsset(
                name: "Mytty.zip",
                downloadURL: URL(
                    string: "https://github.com/m-tkg/Mytty/releases/download/v\(version)/Mytty.zip"
                )!,
                size: 1,
                sha256: String(repeating: "0", count: 64)
            )
        )
    }
}

private struct StubUpdateChecker: ApplicationUpdateChecking {
    let release: ApplicationUpdateRelease

    func latestRelease(
        includePrereleases: Bool
    ) async throws -> ApplicationUpdateRelease {
        release
    }
}

private actor RecordingUpdateChecker: ApplicationUpdateChecking {
    private let release: ApplicationUpdateRelease
    private(set) var receivedIncludePrereleases: [Bool] = []

    init(release: ApplicationUpdateRelease) {
        self.release = release
    }

    func latestRelease(
        includePrereleases: Bool
    ) async throws -> ApplicationUpdateRelease {
        receivedIncludePrereleases.append(includePrereleases)
        return release
    }
}

private actor RecordingUpdateInstaller: ApplicationUpdateInstalling {
    private var releases: [ApplicationUpdateRelease] = []

    func install(_ release: ApplicationUpdateRelease) async throws {
        releases.append(release)
    }

    func installedReleases() -> [ApplicationUpdateRelease] {
        releases
    }
}
