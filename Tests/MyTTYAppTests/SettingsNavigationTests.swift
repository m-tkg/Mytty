import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Settings navigation")
struct SettingsNavigationTests {
    private let localizer = MyTTYLocalizer(language: .english)

    @Test("offers the consolidated settings categories in display order")
    func categories() {
        #expect(
            SettingsSection.allCases
                == [
                    .general, .shell, .agents, .orchestration, .keyBindings,
                    .remote, .update,
                ]
        )
        #expect(
            SettingsSection.allCases.map { localizer[$0.textKey] }
                == [
                    "General", "Shell", "Agents", "Orchestration",
                    "Key Bindings", "iOS Remote Access", "Update",
                ]
        )
    }

    @Test("searches categories using section and setting names")
    func search() {
        #expect(SettingsSection.general.matches("language", localizer: localizer))
        #expect(SettingsSection.general.matches("toast", localizer: localizer))
        #expect(SettingsSection.general.matches("confirmation", localizer: localizer))
        #expect(!SettingsSection.general.matches("recording", localizer: localizer))
        #expect(SettingsSection.shell.matches("opacity", localizer: localizer))
        #expect(SettingsSection.shell.matches("suggestion", localizer: localizer))
        #expect(SettingsSection.keyBindings.matches("shortcut", localizer: localizer))
        #expect(SettingsSection.agents.matches("cursor", localizer: localizer))
        #expect(
            SettingsSection.orchestration.matches(
                "mytty-ctl",
                localizer: localizer
            )
        )
        #expect(
            SettingsSection.orchestration.matches(
                "pane team",
                localizer: localizer
            )
        )
        #expect(
            SettingsSection.orchestration.matches(
                "AGENTS.md",
                localizer: localizer
            )
        )
        #expect(!SettingsSection.orchestration.matches("cursor", localizer: localizer))
        #expect(SettingsSection.remote.matches("pairing", localizer: localizer))
        #expect(SettingsSection.update.matches("release", localizer: localizer))
        #expect(!SettingsSection.general.matches("cursor", localizer: localizer))
    }

    @Test("offers every application command as a configurable key binding")
    func keyBindingCoverage() {
        let commands = KeyBindingSettingsCatalog.groups.flatMap(\.commands)

        #expect(commands.contains(.showPaneList))
        #expect(!MyTTYCommand.allCases.map(\.rawValue).contains(
            "toggle-attention"
        ))
        #expect(commands.count == Set(commands).count)
        // The on-device model commands are macOS 26+ UI only, so their
        // binding rows are intentionally absent below that.
        var expected = Set(MyTTYCommand.allCases)
        if #unavailable(macOS 26) {
            expected.remove(.explainPane)
            expected.remove(.composeOneLiner)
            expected.remove(.summarizeLastCommand)
        }
        #expect(Set(commands) == expected)
    }
}
