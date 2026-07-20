import AppKit

enum ApplicationIcon {
    static let image: NSImage? = {
        guard let url = ApplicationResources.resourceURL(
            named: "AppIcon",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }()
}

@MainActor
enum ApplicationAlert {
    static func make(style: NSAlert.Style = .informational) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.icon = ApplicationIcon.image
        return alert
    }
}
