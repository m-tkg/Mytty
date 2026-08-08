import AppKit

/// The bundled GitHub mark, loaded once as a template image so both the
/// window status bar (SwiftUI) and the per-pane status bar (AppKit) show the
/// same icon and tint it with the surrounding label color.
///
/// `nil` when the resource is missing from the bundle; callers fall back to
/// the `link` SF Symbol rather than showing nothing.
enum GitHubMarkImageSource {
    static let image: NSImage? = {
        guard let url = ApplicationResources.resourceURL(
            named: "mark-github-16",
            withExtension: "svg"
        ), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    /// The mark, or the `link` SF Symbol standing in for it.
    @MainActor
    static func imageOrFallback(accessibilityDescription: String?) -> NSImage? {
        if let image { return image }
        return NSImage(
            systemSymbolName: "link",
            accessibilityDescription: accessibilityDescription
        )
    }
}
