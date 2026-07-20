import Foundation
import Testing

@testable import MyTTYCore

@Suite("Application paths")
struct ApplicationPathsTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private let temporary = URL(
        fileURLWithPath: "/private/tmp/session/",
        isDirectory: true
    )

    @Test("stores user-editable configuration under XDG config home")
    func configurationPaths() {
        let paths = ApplicationPaths(homeDirectory: home, temporaryDirectory: temporary)

        #expect(paths.configurationDirectory.path == "/Users/tester/.config/mytty")
        #expect(paths.appConfiguration.path == "/Users/tester/.config/mytty/config.toml")
        #expect(paths.terminalConfiguration.path == "/Users/tester/.config/mytty/terminal.conf")
        #expect(paths.agentConfiguration.path == "/Users/tester/.config/mytty/agents.toml")
    }

    @Test("keeps runtime state out of the configuration directory")
    func runtimePaths() {
        let paths = ApplicationPaths(homeDirectory: home, temporaryDirectory: temporary)

        #expect(
            paths.applicationSupportDirectory.path
                == "/Users/tester/Library/Application Support/mytty"
        )
        #expect(paths.database.path == "/Users/tester/Library/Application Support/mytty/mytty.sqlite")
        #expect(
            paths.remoteDevices.path
                == "/Users/tester/Library/Application Support/mytty/remote-devices.json"
        )
        #expect(paths.logDirectory.path == "/Users/tester/Library/Logs/mytty")
        #expect(
            paths.controlSocket.path
                == "/private/tmp/session/com.m-tkg.mytty/mytty.sock"
        )
    }

    @Test("isolates development configuration and runtime state")
    func developmentPaths() {
        let paths = ApplicationPaths(
            homeDirectory: home,
            temporaryDirectory: temporary,
            profile: .development
        )

        #expect(
            paths.configurationDirectory.path
                == "/Users/tester/.config/mytty-dev"
        )
        #expect(
            paths.applicationSupportDirectory.path
                == "/Users/tester/Library/Application Support/mytty-dev"
        )
        #expect(paths.logDirectory.path == "/Users/tester/Library/Logs/mytty-dev")
        #expect(
            paths.controlSocket.path
                == "/private/tmp/session/com.m-tkg.mytty.dev/mytty.sock"
        )
    }
}
