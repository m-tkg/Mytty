import Foundation
import Security

protocol ApplicationUpdateChecking: Sendable {
    func latestRelease(
        includePrereleases: Bool
    ) async throws -> ApplicationUpdateRelease
}

protocol ApplicationUpdateInstalling: Sendable {
    func install(_ release: ApplicationUpdateRelease) async throws
}

extension GitHubReleaseClient: ApplicationUpdateChecking {}

struct ApplicationUpdateInstaller: ApplicationUpdateInstalling, Sendable {
    private let currentApplicationURL: URL
    private let session: URLSession

    init(
        currentApplicationURL: URL = Bundle.main.bundleURL,
        session: URLSession = .shared
    ) {
        self.currentApplicationURL = currentApplicationURL
        self.session = session
    }

    func install(_ release: ApplicationUpdateRelease) async throws {
        guard currentApplicationURL.pathExtension.lowercased() == "app" else {
            throw ApplicationUpdateError.applicationNotInstalled
        }
        try ApplicationCodeSignatureVerifier.validate(currentApplicationURL)

        let archive = try await download(release.asset)
        defer { try? FileManager.default.removeItem(at: archive) }
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mytty-update-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: extractionDirectory) }
        try FileManager.default.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        try await UpdateCommandRunner.run(
            executable: "/usr/bin/ditto",
            arguments: [
                "-x", "-k", archive.path, extractionDirectory.path,
            ],
            failure: .invalidArchive
        )
        let candidate = extractionDirectory.appendingPathComponent(
            "Mytty.app",
            isDirectory: true
        )
        try ApplicationUpdatePackageValidator.validate(
            candidate,
            expectedVersion: release.version
        )
        try ApplicationCodeSignatureVerifier.validate(candidate)
        try await UpdateCommandRunner.run(
            executable: "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "execute", candidate.path],
            failure: .gatekeeperRejected
        )
        try ApplicationBundleReplacer().replaceApplication(
            at: currentApplicationURL,
            with: candidate
        )
    }

    private func download(_ asset: ApplicationUpdateAsset) async throws -> URL {
        var request = URLRequest(url: asset.downloadURL)
        request.timeoutInterval = 120
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mytty", forHTTPHeaderField: "User-Agent")
        guard let (temporaryURL, response) = try? await session.download(
            for: request
        ), let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200,
        trustedDownloadResponse(httpResponse),
        let size = try? temporaryURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize,
        Int64(size) == asset.size
        else { throw ApplicationUpdateError.downloadFailed }

        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mytty-release-\(UUID().uuidString).zip",
                isDirectory: false
            )
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: archive)
            let digest = try await Task.detached(priority: .utility) {
                try ApplicationUpdateDigest.sha256Hex(of: archive)
            }.value
            guard digest == asset.sha256 else {
                try? FileManager.default.removeItem(at: archive)
                throw ApplicationUpdateError.checksumMismatch
            }
            return archive
        } catch let error as ApplicationUpdateError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: archive)
            throw ApplicationUpdateError.downloadFailed
        }
    }

    private func trustedDownloadResponse(_ response: HTTPURLResponse) -> Bool {
        guard let url = response.url,
              url.scheme?.lowercased() == "https",
              let host = url.host(percentEncoded: false)?.lowercased()
        else { return false }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }
}

enum ApplicationUpdatePackageValidator {
    static func validate(
        _ applicationURL: URL,
        expectedVersion: ApplicationVersion
    ) throws {
        let values = try applicationURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              applicationURL.lastPathComponent == "Mytty.app",
              !containsSymbolicLink(applicationURL)
        else { throw ApplicationUpdateError.invalidApplication }

        let plistURL = applicationURL.appendingPathComponent(
            "Contents/Info.plist",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              object["CFBundleIdentifier"] as? String
                == ApplicationIdentity.bundleIdentifier,
              let rawVersion = object["CFBundleShortVersionString"] as? String,
              ApplicationVersion(rawVersion) == expectedVersion
        else { throw ApplicationUpdateError.invalidApplication }
    }

    private static func containsSymbolicLink(_ root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return true }
        for case let url as URL in enumerator {
            if (try? url.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink) == true {
                return true
            }
        }
        return false
    }
}

enum ApplicationCodeSignatureVerifier {
    static func validate(_ applicationURL: URL) throws {
        let requirementText = "anchor apple generic"
            + " and identifier \"\(ApplicationIdentity.bundleIdentifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \""
            + ApplicationIdentity.developerTeamIdentifier
            + "\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess,
        let requirement
        else { throw ApplicationUpdateError.invalidSignature }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            applicationURL.standardizedFileURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode
        else { throw ApplicationUpdateError.invalidSignature }

        let rawFlags = kSecCSCheckAllArchitectures
            | kSecCSCheckNestedCode
            | kSecCSStrictValidate
            | kSecCSRestrictSymlinks
            | kSecCSRestrictToAppLike
        guard SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: rawFlags),
            requirement
        ) == errSecSuccess else {
            throw ApplicationUpdateError.invalidSignature
        }
    }
}

enum UpdateCommandRunner {
    static func run(
        executable: String,
        arguments: [String],
        failure: ApplicationUpdateError,
        timeout: TimeInterval = 120
    ) async throws {
        let succeeded = await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return false
            }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                return false
            }
            return process.terminationStatus == 0
        }.value
        guard succeeded else { throw failure }
    }
}
