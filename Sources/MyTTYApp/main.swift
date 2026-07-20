import AppKit

private let application = NSApplication.shared
private let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.applicationIconImage = ApplicationIcon.image
application.dockTile.badgeLabel = ApplicationIdentity.dockBadge
application.mainMenu = delegate.makeMainMenu()
application.delegate = delegate
application.run()
withExtendedLifetime(delegate) {}
