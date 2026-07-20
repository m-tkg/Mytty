import Foundation

enum ApplicationResources {
    private static let bundleName = "mytty_MyTTYApp.bundle"

    static func resourceURL(
        named name: String,
        withExtension pathExtension: String
    ) -> URL? {
        resourceURL(
            named: name,
            withExtension: pathExtension,
            searchRoots: defaultSearchRoots
        )
    }

    static func resourceURL(
        named name: String,
        withExtension pathExtension: String,
        searchRoots: [URL]
    ) -> URL? {
        let filename = name + "." + pathExtension
        var visited = Set<String>()

        for root in searchRoots {
            let bundle = root.lastPathComponent == bundleName
                ? root
                : root.appendingPathComponent(bundleName, isDirectory: true)
            let resourceDirectories = [
                bundle,
                bundle.appendingPathComponent(
                    "Contents/Resources",
                    isDirectory: true
                ),
            ]

            for directory in resourceDirectories {
                let candidate = directory
                    .appendingPathComponent(filename, isDirectory: false)
                    .standardizedFileURL
                guard visited.insert(candidate.path).inserted else { continue }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(
                    atPath: candidate.path,
                    isDirectory: &isDirectory
                ), !isDirectory.boolValue else { continue }
                return candidate
            }
        }

        return nil
    }

    static func executableSearchRoots(for executable: URL) -> [URL] {
        var roots: [URL] = []
        var directory = executable.standardizedFileURL
            .deletingLastPathComponent()

        for _ in 0..<4 {
            roots.append(directory)
            roots.append(
                directory.appendingPathComponent("Resources", isDirectory: true)
            )
            let parent = directory.deletingLastPathComponent()
            guard parent != directory else { break }
            directory = parent
        }
        return roots
    }

    static func commandLineSearchRoots(arguments: [String]) -> [URL] {
        guard let executable = arguments.first else { return [] }
        var candidates = [URL(fileURLWithPath: executable)]
        #if DEBUG
        candidates.append(contentsOf: arguments.dropFirst().compactMap {
            let candidate = URL(fileURLWithPath: $0)
            return candidate.pathExtension == "xctest" ? candidate : nil
        })
        #endif
        return candidates.flatMap(executableSearchRoots(for:))
    }

    static func bundleSearchRoots(
        bundleURL: URL,
        resourceURL: URL?
    ) -> [URL] {
        var roots = [bundleURL]
        if let resourceURL {
            roots.insert(resourceURL, at: 0)
        }
        roots.append(contentsOf: executableSearchRoots(for: bundleURL))
        return roots
    }

    private static var defaultSearchRoots: [URL] {
        var roots: [URL] = []
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            roots.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        roots.append(contentsOf: bundleSearchRoots(
            bundleURL: Bundle.main.bundleURL,
            resourceURL: Bundle.main.resourceURL
        ))
        let tokenBundle = Bundle(for: ApplicationResourceBundleToken.self)
        roots.append(contentsOf: bundleSearchRoots(
            bundleURL: tokenBundle.bundleURL,
            resourceURL: tokenBundle.resourceURL
        ))

        roots.append(contentsOf: commandLineSearchRoots(
            arguments: CommandLine.arguments
        ))
        return roots
    }
}

private final class ApplicationResourceBundleToken {}
