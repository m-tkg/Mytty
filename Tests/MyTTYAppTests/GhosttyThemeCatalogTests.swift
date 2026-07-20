import Foundation
import Testing

@testable import MyTTYApp

@Suite("Ghostty theme catalog")
struct GhosttyThemeCatalogTests {
    @Test("parses terminal preview colors from a Ghostty theme")
    func previewColors() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let themes = root.appendingPathComponent("themes", isDirectory: true)
        try writeTheme(
            """
            # Theme colors can appear in any palette order.
            palette = 2=#55AA77
            foreground = #F2F2F2
            palette = 0=#111111
            background = #101820
            palette = 1=#CC3344
            """,
            named: "Preview Theme",
            to: themes
        )

        let previews = GhosttyThemeCatalog.availableThemes(
            bundledThemesDirectory: themes,
            userThemesDirectory: nil
        )
        let preview = try #require(previews.first)

        #expect(preview.name == "Preview Theme")
        #expect(preview.backgroundHex == "101820")
        #expect(preview.foregroundHex == "f2f2f2")
        #expect(preview.paletteHex == ["111111", "cc3344", "55aa77"])
    }

    @Test("uses user theme colors when a name overrides a bundled theme")
    func userThemeOverride() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        try writeTheme(
            "background = #111111\nforeground = #eeeeee",
            named: "Shared Theme",
            to: bundled
        )
        try writeTheme(
            "background = #fafafa\nforeground = #202020",
            named: "Shared Theme",
            to: user
        )

        let previews = GhosttyThemeCatalog.availableThemes(
            bundledThemesDirectory: bundled,
            userThemesDirectory: user
        )
        let preview = try #require(previews.first)

        #expect(previews.map(\.name) == ["Shared Theme"])
        #expect(preview.backgroundHex == "fafafa")
        #expect(preview.foregroundHex == "202020")
    }

    @Test("merges bundled and user themes as sorted unique names")
    func availableNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        try writeTheme("Rose Pine", to: bundled)
        try writeTheme("3024 Night", to: bundled)
        try writeTheme("Rose Pine", to: user)
        try writeTheme("User Theme", to: user)
        try writeTheme(".DS_Store", to: user)
        try FileManager.default.createDirectory(
            at: user.appendingPathComponent("Nested", isDirectory: true),
            withIntermediateDirectories: true
        )

        let names = GhosttyThemeCatalog.availableNames(
            bundledThemesDirectory: bundled,
            userThemesDirectory: user
        )

        #expect(names == ["3024 Night", "Rose Pine", "User Theme"])
    }

    @Test("locates bundled resources before a development checkout")
    func resourceLocation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleResources = root
            .appendingPathComponent("bundle", isDirectory: true)
        let bundledGhostty = bundleResources
            .appendingPathComponent("ghostty", isDirectory: true)
        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        let developmentGhostty = checkout
            .appendingPathComponent(
                "Vendor/ghostty/zig-out/share/ghostty",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: bundledGhostty.appendingPathComponent("themes"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: developmentGhostty.appendingPathComponent("themes"),
            withIntermediateDirectories: true
        )

        #expect(GhosttyResourceLocator.resolve(
            bundleResourcesDirectory: bundleResources,
            currentDirectory: checkout
        ) == bundledGhostty)

        try FileManager.default.removeItem(at: bundledGhostty)

        #expect(GhosttyResourceLocator.resolve(
            bundleResourcesDirectory: bundleResources,
            currentDirectory: checkout
        ) == developmentGhostty)
    }

    private func writeTheme(_ name: String, to directory: URL) throws {
        try writeTheme(
            "background = 000000\n",
            named: name,
            to: directory
        )
    }

    private func writeTheme(
        _ contents: String,
        named name: String,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(
            to: directory.appendingPathComponent(name)
        )
    }
}
