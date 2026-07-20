import Foundation
import MyTTYCore

/// The privileged clamshell helper daemon. Shipped inside the app bundle
/// at `Contents/MacOS/mytty-clamshell-helper`, registered as a launchd
/// daemon through `SMAppService`, and reached over XPC. It only ever
/// runs `pmset disablesleep`, and only for a signed Mytty build.

/// The enclosing app bundle: .../X.app/Contents/MacOS/mytty-clamshell-helper.
/// launchd's BundleProgram passes a bundle-relative argv[0], so resolve
/// the executable through dyld, which always has the absolute path.
private func enclosingBundleIdentifier() -> String? {
    guard let executableURL = Bundle.main.executableURL else { return nil }
    let executable = executableURL.resolvingSymlinksInPath()
    let bundleURL = executable
        .deletingLastPathComponent()  // MacOS
        .deletingLastPathComponent()  // Contents
        .deletingLastPathComponent()  // X.app
    guard bundleURL.pathExtension == "app",
          let identifier = Bundle(url: bundleURL)?.bundleIdentifier,
          identifier.hasPrefix("com.m-tkg.mytty"),
          identifier.count < 64
    else { return nil }
    return identifier
}

private func runPMSet(disableSleep: Bool) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["disablesleep", disableSleep ? "1" : "0"]
    do {
        try process.run()
    } catch {
        return false
    }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let exported: ClamshellHelperExported

    init(core: ClamshellHelperCore) {
        exported = ClamshellHelperExported(core: core)
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // Only a Mytty build signed by this project's team may drive the
        // daemon; everything else is rejected before any message flows.
        let requirement = #"anchor apple generic and "#
            + #"(identifier "com.m-tkg.mytty" or identifier "com.m-tkg.mytty.dev") and "#
            + #"certificate leaf[subject.OU] = "G72M73C546""#
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(
            with: ClamshellHelperXPC.self
        )
        connection.exportedObject = exported
        connection.resume()
        return true
    }
}

private final class ClamshellHelperExported: NSObject, ClamshellHelperXPC {
    private let core: ClamshellHelperCore

    init(core: ClamshellHelperCore) {
        self.core = core
    }

    func setKeepAwake(
        _ enabled: Bool,
        watchedPID: Int32,
        reply: @escaping @Sendable (Bool) -> Void
    ) {
        reply(core.setKeepAwake(enabled, watchedPID: watchedPID))
    }
}

guard let bundleIdentifier = enclosingBundleIdentifier() else {
    // Not running from a Mytty bundle; refuse to serve.
    exit(1)
}

private let core = ClamshellHelperCore(setDisableSleep: runPMSet)
private let delegate = HelperListenerDelegate(core: core)
private let listener = NSXPCListener(
    machServiceName: ClamshellHelperService.label(
        bundleIdentifier: bundleIdentifier
    )
)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
