import Foundation

public enum ApplicationPathProfile: Sendable {
    case release
    case development

    fileprivate var directoryName: String {
        switch self {
        case .release: "mytty"
        case .development: "mytty-dev"
        }
    }

    fileprivate var runtimeIdentifier: String {
        switch self {
        case .release: "com.m-tkg.mytty"
        case .development: "com.m-tkg.mytty.dev"
        }
    }

    /// The name to use when symlinking `mytty-ctl` onto a user's `PATH`
    /// (e.g. into `~/.local/bin`). Development builds get a distinct name
    /// so installing Mytty Dev's link never steals the release build's.
    public var commandLineToolName: String {
        switch self {
        case .release: "mytty-ctl"
        case .development: "mytty-ctl-dev"
        }
    }
}

public struct ApplicationPaths: Sendable {
    public let configurationDirectory: URL
    public let appConfiguration: URL
    public let terminalConfiguration: URL
    public let agentConfiguration: URL

    public let applicationSupportDirectory: URL
    public let database: URL
    public let remoteDevices: URL
    public let logDirectory: URL
    public let controlSocket: URL
    public let aiControlSocket: URL

    public init(
        homeDirectory: URL,
        temporaryDirectory: URL,
        profile: ApplicationPathProfile = .release
    ) {
        configurationDirectory = homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(profile.directoryName, isDirectory: true)
        appConfiguration = configurationDirectory
            .appendingPathComponent("config.toml", isDirectory: false)
        terminalConfiguration = configurationDirectory
            .appendingPathComponent("terminal.conf", isDirectory: false)
        agentConfiguration = configurationDirectory
            .appendingPathComponent("agents.toml", isDirectory: false)

        applicationSupportDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(profile.directoryName, isDirectory: true)
        database = applicationSupportDirectory
            .appendingPathComponent("mytty.sqlite", isDirectory: false)
        remoteDevices = applicationSupportDirectory
            .appendingPathComponent("remote-devices.json", isDirectory: false)
        logDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(profile.directoryName, isDirectory: true)
        let runtimeDirectory = temporaryDirectory
            .appendingPathComponent(
                profile.runtimeIdentifier,
                isDirectory: true
            )
        controlSocket = runtimeDirectory
            .appendingPathComponent("mytty.sock", isDirectory: false)
        aiControlSocket = runtimeDirectory
            .appendingPathComponent("mytty-ctl.sock", isDirectory: false)
    }
}
