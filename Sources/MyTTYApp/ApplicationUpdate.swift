import CryptoKit
import Foundation

struct ApplicationVersion: Comparable, CustomStringConvertible, Hashable,
    Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    /// Dot-separated pre-release identifiers (e.g. `["beta", "1"]` for
    /// `-beta.1`). Empty for a normal release.
    let prereleaseIdentifiers: [String]

    var isPrerelease: Bool { !prereleaseIdentifiers.isEmpty }

    init?(_ value: String) {
        let normalized = value.hasPrefix("v")
            ? String(value.dropFirst())
            : value
        let hyphenIndex = normalized.firstIndex(of: "-")
        let core = hyphenIndex.map { String(normalized[..<$0]) } ?? normalized
        let components = core.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0,
              minor >= 0,
              patch >= 0
        else { return nil }

        if let hyphenIndex {
            let raw = normalized[normalized.index(after: hyphenIndex)...]
            let identifiers = raw.split(
                separator: ".",
                omittingEmptySubsequences: false
            ).map(String.init)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy(Self.isValidIdentifier)
            else { return nil }
            prereleaseIdentifiers = identifiers
        } else {
            prereleaseIdentifiers = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prereleaseIdentifiers.isEmpty else { return core }
        return core + "-" + prereleaseIdentifiers.joined(separator: ".")
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let lhsCore = (lhs.major, lhs.minor, lhs.patch)
        let rhsCore = (rhs.major, rhs.minor, rhs.patch)
        guard lhsCore == rhsCore else { return lhsCore < rhsCore }

        // Same major.minor.patch: a release outranks any of its own
        // pre-releases, and pre-releases compare identifier by identifier.
        switch (lhs.prereleaseIdentifiers.isEmpty, rhs.prereleaseIdentifiers.isEmpty) {
        case (true, true), (true, false):
            return false
        case (false, true):
            return true
        case (false, false):
            return comparePrerelease(
                lhs.prereleaseIdentifiers,
                rhs.prereleaseIdentifiers
            )
        }
    }

    private static func comparePrerelease(
        _ lhs: [String],
        _ rhs: [String]
    ) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left < right
            }
        }
        return lhs.count < rhs.count
    }
}

struct ApplicationUpdateAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let size: Int64
    let sha256: String
}

struct ApplicationUpdateRelease: Equatable, Sendable {
    let version: ApplicationVersion
    let tagName: String
    let pageURL: URL
    let asset: ApplicationUpdateAsset
}

enum ApplicationUpdateError: Error, Equatable, Sendable {
    case invalidRelease
    case requestFailed
    case downloadFailed
    case checksumMismatch
    case invalidArchive
    case invalidApplication
    case invalidSignature
    case gatekeeperRejected
    case applicationNotInstalled
    case installationFailed
}

enum GitHubReleaseParser {
    private static let maximumAssetSize: Int64 = 256 * 1_024 * 1_024

    private struct Response: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int64
            let digest: String?

            private enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
                case digest
            }
        }

        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    static func release(
        from data: Data,
        includePrereleases: Bool = false
    ) throws -> ApplicationUpdateRelease {
        guard let response = try? JSONDecoder().decode(Response.self, from: data)
        else { throw ApplicationUpdateError.invalidRelease }
        return try parse(response, includePrereleases: includePrereleases)
    }

    /// Picks the newest release from a `GET /releases` listing, which GitHub
    /// returns ordered by creation date, descending. Entries this app
    /// cannot trust (malformed tag, untrusted asset URL, filtered-out
    /// pre-release, ...) are skipped rather than failing the whole check.
    static func newestRelease(
        fromList data: Data,
        includePrereleases: Bool
    ) throws -> ApplicationUpdateRelease {
        guard let responses = try? JSONDecoder().decode(
            [Response].self,
            from: data
        ) else { throw ApplicationUpdateError.invalidRelease }
        for response in responses {
            if let release = try? parse(
                response,
                includePrereleases: includePrereleases
            ) {
                return release
            }
        }
        throw ApplicationUpdateError.invalidRelease
    }

    private static func parse(
        _ response: Response,
        includePrereleases: Bool
    ) throws -> ApplicationUpdateRelease {
        guard !response.draft,
              includePrereleases || !response.prerelease,
              let version = ApplicationVersion(response.tagName),
              trustedReleasePage(response.htmlURL, tagName: response.tagName),
              let rawAsset = response.assets.first(where: {
                  $0.name == "Mytty.zip"
              }),
              rawAsset.size > 0,
              rawAsset.size <= maximumAssetSize,
              trustedAssetURL(
                  rawAsset.browserDownloadURL,
                  tagName: response.tagName
              ),
              let digest = rawAsset.digest?.lowercased(),
              digest.hasPrefix("sha256:"),
              validSHA256(String(digest.dropFirst("sha256:".count)))
        else { throw ApplicationUpdateError.invalidRelease }

        return ApplicationUpdateRelease(
            version: version,
            tagName: response.tagName,
            pageURL: response.htmlURL,
            asset: ApplicationUpdateAsset(
                name: rawAsset.name,
                downloadURL: rawAsset.browserDownloadURL,
                size: rawAsset.size,
                sha256: String(digest.dropFirst("sha256:".count))
            )
        )
    }

    private static func trustedReleasePage(
        _ url: URL,
        tagName: String
    ) -> Bool {
        trustedGitHubURL(url)
            && url.path == "/m-tkg/Mytty/releases/tag/\(tagName)"
    }

    private static func trustedAssetURL(
        _ url: URL,
        tagName: String
    ) -> Bool {
        trustedGitHubURL(url)
            && url.path
                == "/m-tkg/Mytty/releases/download/\(tagName)/Mytty.zip"
    }

    private static func trustedGitHubURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host(percentEncoded: false)?.lowercased() == "github.com"
            && url.user == nil
            && url.password == nil
            && url.port == nil
            && url.query == nil
            && url.fragment == nil
    }

    private static func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}

struct GitHubReleaseClient: Sendable {
    private static let latestEndpoint = URL(
        string: "https://api.github.com/repos/m-tkg/Mytty/releases/latest"
    )!
    // GitHub lists releases newest-created-first; ten is comfortably more
    // than this project publishes between stable releases.
    private static let listEndpoint = URL(
        string: "https://api.github.com/repos/m-tkg/Mytty/releases?per_page=10"
    )!

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestRelease(
        includePrereleases: Bool = false
    ) async throws -> ApplicationUpdateRelease {
        guard includePrereleases else {
            return try GitHubReleaseParser.release(
                from: try await fetch(Self.latestEndpoint)
            )
        }
        return try GitHubReleaseParser.newestRelease(
            fromList: try await fetch(Self.listEndpoint),
            includePrereleases: true
        )
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("Mytty", forHTTPHeaderField: "User-Agent")
        request.setValue(
            "2022-11-28",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { throw ApplicationUpdateError.requestFailed }
        return data
    }
}

enum ApplicationUpdateDigest {
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024),
              !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct ApplicationBundleReplacer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func replaceApplication(at installed: URL, with candidate: URL) throws {
        guard installed.pathExtension.lowercased() == "app",
              candidate.pathExtension.lowercased() == "app"
        else { throw ApplicationUpdateError.installationFailed }

        let replacementDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: installed,
            create: true
        )
        defer { try? fileManager.removeItem(at: replacementDirectory) }
        let staged = replacementDirectory.appendingPathComponent(
            installed.lastPathComponent,
            isDirectory: true
        )
        try fileManager.copyItem(at: candidate, to: staged)
        do {
            _ = try fileManager.replaceItemAt(
                installed,
                withItemAt: staged
            )
        } catch {
            throw ApplicationUpdateError.installationFailed
        }
    }
}
