import Foundation

struct GhosttyThemePreview: Equatable, Identifiable, Sendable {
    static let fallbackBackgroundHex = "1e1e1e"
    static let fallbackForegroundHex = "d4d4d4"

    let name: String
    let backgroundHex: String
    let foregroundHex: String
    let paletteHex: [String]

    var id: String { name }

    init(
        name: String,
        backgroundHex: String,
        foregroundHex: String,
        paletteHex: [String] = []
    ) {
        self.name = name
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.paletteHex = paletteHex
    }

    init(name: String, data: Data) {
        var backgroundHex: String?
        var foregroundHex: String?
        var palette: [Int: String] = [:]

        for rawLine in String(decoding: data, as: UTF8.self).split(
            whereSeparator: \Character.isNewline
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  let assignment = Self.assignment(in: line)
            else { continue }

            switch assignment.key {
            case "background":
                backgroundHex = Self.normalizedHex(assignment.value)
            case "foreground":
                foregroundHex = Self.normalizedHex(assignment.value)
            case "palette":
                guard let color = Self.paletteColor(assignment.value) else {
                    continue
                }
                palette[color.index] = color.hex
            default:
                continue
            }
        }

        self.name = name
        self.backgroundHex = backgroundHex ?? Self.fallbackBackgroundHex
        self.foregroundHex = foregroundHex ?? Self.fallbackForegroundHex
        paletteHex = palette.keys.sorted().compactMap { palette[$0] }
    }

    private static func assignment(
        in line: String
    ) -> (key: String, value: String)? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (
            String(parts[0]).trimmingCharacters(in: .whitespaces),
            String(parts[1]).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func paletteColor(
        _ value: String
    ) -> (index: Int, hex: String)? {
        guard let assignment = assignment(in: value),
              let index = Int(assignment.key),
              let hex = normalizedHex(assignment.value)
        else { return nil }
        return (index, hex)
    }

    private static func normalizedHex(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespaces)
            .trimmingPrefix("#")
            .lowercased()
        let hexDigits = CharacterSet(
            charactersIn: "0123456789abcdef"
        )
        guard normalized.count == 6,
              normalized.unicodeScalars.allSatisfy(
                  hexDigits.contains
              )
        else { return nil }
        return normalized
    }
}

enum GhosttyResourceLocator {
    static func current(
        bundleResourcesDirectory: URL? = Bundle.main.resourceURL,
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        fileManager: FileManager = .default
    ) -> URL? {
        resolve(
            bundleResourcesDirectory: bundleResourcesDirectory,
            currentDirectory: currentDirectory,
            fileManager: fileManager
        )
    }

    static func resolve(
        bundleResourcesDirectory: URL?,
        currentDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            bundleResourcesDirectory?.appendingPathComponent(
                "ghostty",
                isDirectory: true
            ),
            currentDirectory.appendingPathComponent(
                "Vendor/ghostty/zig-out/share/ghostty",
                isDirectory: true
            ),
        ].compactMap { $0 }
        return candidates.first { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(
                atPath: candidate
                    .appendingPathComponent("themes", isDirectory: true)
                    .path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
        }
    }
}

enum GhosttyThemeCatalog {
    static func currentThemes(
        resourcesDirectory: URL? = GhosttyResourceLocator.current(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [GhosttyThemePreview] {
        let directories = themeDirectories(
            resourcesDirectory: resourcesDirectory,
            homeDirectory: homeDirectory,
            environment: environment
        )
        return availableThemes(
            bundledThemesDirectory: directories.bundled,
            userThemesDirectory: directories.user,
            fileManager: fileManager
        )
    }

    static func currentNames(
        resourcesDirectory: URL? = GhosttyResourceLocator.current(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [String] {
        let directories = themeDirectories(
            resourcesDirectory: resourcesDirectory,
            homeDirectory: homeDirectory,
            environment: environment
        )
        return availableNames(
            bundledThemesDirectory: directories.bundled,
            userThemesDirectory: directories.user,
            fileManager: fileManager
        )
    }

    static func availableNames(
        bundledThemesDirectory: URL?,
        userThemesDirectory: URL?,
        fileManager: FileManager = .default
    ) -> [String] {
        themeFiles(
            bundledThemesDirectory: bundledThemesDirectory,
            userThemesDirectory: userThemesDirectory,
            fileManager: fileManager
        ).keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func availableThemes(
        bundledThemesDirectory: URL?,
        userThemesDirectory: URL?,
        fileManager: FileManager = .default
    ) -> [GhosttyThemePreview] {
        themeFiles(
            bundledThemesDirectory: bundledThemesDirectory,
            userThemesDirectory: userThemesDirectory,
            fileManager: fileManager
        ).map { name, url in
            GhosttyThemePreview(
                name: name,
                data: (try? Data(contentsOf: url)) ?? Data()
            )
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func themeDirectories(
        resourcesDirectory: URL?,
        homeDirectory: URL,
        environment: [String: String]
    ) -> (bundled: URL?, user: URL) {
        let configDirectory = environment["XDG_CONFIG_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? homeDirectory.appendingPathComponent(".config", isDirectory: true)
        return (
            resourcesDirectory?.appendingPathComponent(
                "themes",
                isDirectory: true
            ),
            configDirectory.appendingPathComponent(
                "ghostty/themes",
                isDirectory: true
            )
        )
    }

    private static func themeFiles(
        bundledThemesDirectory: URL?,
        userThemesDirectory: URL?,
        fileManager: FileManager
    ) -> [String: URL] {
        [bundledThemesDirectory, userThemesDirectory]
            .compactMap { $0 }
            .reduce(into: [String: URL]()) { result, directory in
                guard let urls = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { return }
                for url in urls {
                    guard (try? url.resourceValues(
                        forKeys: [.isRegularFileKey]
                    ).isRegularFile) == true else { continue }
                    result[url.lastPathComponent] = url
                }
            }
    }
}
