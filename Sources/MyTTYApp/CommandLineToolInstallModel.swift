import Foundation

/// The filesystem operations `CommandLineToolInstallModel` needs to manage
/// a symlink into `~/.local/bin`, split out (same reasoning as
/// `DefaultTerminalRegistering`) so tests can point the model at a
/// throwaway directory without touching the developer's real `~/.local/bin`.
@MainActor
protocol CommandLineToolLinking: AnyObject {
    func ensureDirectoryExists(at directory: URL) throws
    /// The resolved, absolute destination of the symlink at `linkURL`, or
    /// `nil` if nothing there is a symlink (including nothing at all).
    func existingLinkDestination(at linkURL: URL) -> URL?
    /// `true` if `linkURL` is occupied by something that is *not* a
    /// symlink — a real file or directory we must not overwrite.
    func isNonSymlinkItem(at linkURL: URL) -> Bool
    func createSymbolicLink(at linkURL: URL, pointingTo targetURL: URL) throws
}

@MainActor
final class FileManagerCommandLineToolLinker: CommandLineToolLinking {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ensureDirectoryExists(at directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func existingLinkDestination(at linkURL: URL) -> URL? {
        guard let destination = try? fileManager.destinationOfSymbolicLink(
            atPath: linkURL.path
        ) else { return nil }
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }
        return linkURL.deletingLastPathComponent()
            .appendingPathComponent(destination)
    }

    func isNonSymlinkItem(at linkURL: URL) -> Bool {
        if (try? fileManager.destinationOfSymbolicLink(
            atPath: linkURL.path
        )) != nil {
            return false
        }
        return fileManager.fileExists(atPath: linkURL.path)
    }

    func createSymbolicLink(
        at linkURL: URL,
        pointingTo targetURL: URL
    ) throws {
        try fileManager.createSymbolicLink(
            at: linkURL,
            withDestinationURL: targetURL
        )
    }
}

enum CommandLineToolInstallFailure: Equatable {
    /// Something other than a link to this Mytty build already occupies
    /// the target path — a real file, or a symlink pointing elsewhere.
    case conflict
    /// The directory couldn't be created, or the link couldn't be
    /// written (permissions, disk full, etc).
    case filesystem
}

/// Backs the Settings > General "install to PATH" row: symlinks the
/// installed `mytty-ctl` binary into `~/.local/bin` so it also runs
/// outside Mytty (a plain Terminal.app tab, a script, ...). Panes Mytty
/// itself opens don't need this — see `AgentEventServer.environment(for:)`.
@MainActor
final class CommandLineToolInstallModel: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var isUpdating = false
    @Published private(set) var failure: CommandLineToolInstallFailure?
    @Published private(set) var pathHintNeeded = false

    let linkName: String

    private let executableURL: URL
    private let binDirectory: URL
    private let linker: any CommandLineToolLinking
    private let environmentPath: () -> String?

    var linkURL: URL {
        binDirectory.appendingPathComponent(linkName, isDirectory: false)
    }

    /// A line the caption suggests adding to the user's shell profile when
    /// `~/.local/bin` isn't already searched. `$HOME`-relative on purpose —
    /// this is text for the user to paste, not a path we resolve ourselves.
    var pathExportLine: String {
        "export PATH=\"$HOME/.local/bin:$PATH\""
    }

    init(
        executableURL: URL,
        binDirectory: URL,
        linkName: String,
        linker: any CommandLineToolLinking = FileManagerCommandLineToolLinker(),
        environmentPath: @escaping () -> String? = {
            ProcessInfo.processInfo.environment["PATH"]
        }
    ) {
        self.executableURL = executableURL
        self.binDirectory = binDirectory
        self.linkName = linkName
        self.linker = linker
        self.environmentPath = environmentPath
    }

    func refresh() {
        failure = nil
        if let destination = linker.existingLinkDestination(at: linkURL) {
            isInstalled = canonical(destination) == canonical(executableURL)
        } else {
            isInstalled = false
        }
        updatePathHint()
    }

    func install() {
        guard !isUpdating else { return }
        isUpdating = true
        failure = nil
        defer { isUpdating = false }

        do {
            try linker.ensureDirectoryExists(at: binDirectory)
        } catch {
            isInstalled = false
            failure = .filesystem
            return
        }

        if linker.isNonSymlinkItem(at: linkURL) {
            isInstalled = false
            failure = .conflict
            return
        }

        if let destination = linker.existingLinkDestination(at: linkURL) {
            guard canonical(destination) == canonical(executableURL) else {
                isInstalled = false
                failure = .conflict
                return
            }
            isInstalled = true
            updatePathHint()
            return
        }

        do {
            try linker.createSymbolicLink(
                at: linkURL,
                pointingTo: executableURL
            )
            isInstalled = true
            updatePathHint()
        } catch {
            isInstalled = false
            failure = .filesystem
        }
    }

    private func updatePathHint() {
        guard isInstalled else {
            pathHintNeeded = false
            return
        }
        let directories = (environmentPath() ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
        pathHintNeeded = !directories.contains(Substring(binDirectory.path))
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
