import Foundation
import Testing

@testable import MyTTYCore

@Suite("Preferences stores")
struct PreferencesStoreTests {
    @Test("round trips tab placement while preserving other app settings")
    func applicationPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        analytics = false
        tab-position = "right"
        new-tab-position = "after-current"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.tabPlacement == .right)
        #expect(preferences.newTabPosition == .afterCurrent)

        preferences.tabPlacement = .bottom
        preferences.newTabPosition = .end
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )

        #expect(contents.contains("analytics = false"))
        #expect(contents.contains("tab-position = \"bottom\""))
        #expect(contents.contains("new-tab-position = \"end\""))
        #expect(contents.components(separatedBy: "tab-position").count == 3)
        #expect(try store.load(from: harness.appConfiguration) == preferences)
    }

    @Test("round trips the outer split on hold setting")
    func outerSplitOnHoldPreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(!preferences.outerSplitOnHold)

        preferences.outerSplitOnHold = true
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("pane.outer-split-on-hold = \"true\""))
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        try """
        pane.outer-split-on-hold = "sideways"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("round trips the force ASCII input on focus setting")
    func forceASCIIInputOnFocusPreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(!preferences.forceASCIIInputOnFocus)

        preferences.forceASCIIInputOnFocus = true
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("input.force-ascii-on-focus = \"true\""))
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        try """
        input.force-ascii-on-focus = "sideways"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("round trips the force ASCII input scope setting")
    func forceASCIIInputScopePreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.forceASCIIInputScope == .shellIdleOnly)

        preferences.forceASCIIInputScope = .always
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("input.force-ascii-scope = \"always\""))
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        try """
        input.force-ascii-scope = "sometimes"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("round trips the floating pane edge and global hot key settings")
    func floatingPanePreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.floatingPaneEdge == .top)
        #expect(preferences.floatingPaneGlobalHotKeyEnabled)

        preferences.floatingPaneEdge = .left
        preferences.floatingPaneGlobalHotKeyEnabled = false
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("floating-pane.edge = \"left\""))
        #expect(
            contents.contains(
                "floating-pane.global-hotkey-enabled = \"false\""
            )
        )
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        try """
        floating-pane.edge = "diagonal"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("rejects an unrecognized new tab position")
    func invalidNewTabPosition() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        new-tab-position = "middle"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("persists key binding overrides and explicit removal")
    func keyBindingPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        analytics = false
        keybinding.new-tab = "control+t"
        keybinding.split-right = "none"
        keybinding.toggle-attention = "shift+command+a"
        keybinding.future-command = "command+f"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(
            preferences.keyBindings[.newTab]?.serialized == "control+t"
        )
        #expect(preferences.keyBindings[.splitRight] == nil)
        #expect(
            preferences.keyBindings[.splitDown]?.serialized
                == "control+command+minus"
        )

        preferences.keyBindings[.toggleRecording] = MyTTYKeyBinding(
            key: "i",
            modifiers: [.command, .shift]
        )
        preferences.keyBindings.removeValue(forKey: .closePane)
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )

        #expect(contents.contains("analytics = false"))
        #expect(
            contents.contains(
                "keybinding.toggle-recording = \"shift+command+i\""
            )
        )
        #expect(contents.contains("keybinding.close-pane = \"none\""))
        #expect(!contents.contains("keybinding.toggle-attention"))
        #expect(
            contents.contains(
                "keybinding.future-command = \"command+f\""
            )
        )
        #expect(try store.load(from: harness.appConfiguration) == preferences)
    }

    @Test("round trips launch, confirmation, language, and window settings")
    func applicationBehaviorPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        analytics = false
        language = "japanese"
        on-launch = "new-window"
        confirmation.close-window = "always"
        confirmation.close-pane = "always"
        confirmation.close-tab = "when-process-running"
        confirmation.close-last-pane = "false"
        window.mode = "small"
        show-status-bar = "false"
        recording.show-keys = "true"
        input.show-key-toast = "true"
        autocomplete.enabled = "false"
        agents.prevent-system-sleep = "prevent-while-launched"
        attention.unread-only = "true"
        tab.show-uptime = "true"
        tab.auto-name-agent-tabs = "false"
        agents.pane-team-pointers = "false"
        remote.access-enabled = "true"
        pane.inactive-dimming = "0.45"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.language == .japanese)
        #expect(preferences.launchBehavior == .newWindow)
        #expect(preferences.closeWindowConfirmation == .always)
        #expect(preferences.closePaneConfirmation == .always)
        #expect(preferences.closeTabConfirmation == .whenProcessRunning)
        #expect(!preferences.confirmClosingLastPane)
        #expect(preferences.windowStartupBehavior == .small)
        #expect(!preferences.showStatusBar)
        #expect(preferences.showPressedKeyToast)
        #expect(!preferences.autocompleteEnabled)
        #expect(
            preferences.agentSleepPreventionMode == .preventWhileLaunched
        )
        #expect(preferences.attentionUnreadOnly)
        #expect(preferences.showTabUptime)
        #expect(!preferences.autoNameAgentTabs)
        #expect(!preferences.paneTeamPointersEnabled)
        #expect(preferences.remoteAccessEnabled)
        #expect(preferences.inactivePaneDimming == 0.45)

        preferences.language = .english
        preferences.launchBehavior = .restoreLastSession
        preferences.closeWindowConfirmation = .whenProcessRunning
        preferences.closePaneConfirmation = .whenProcessRunning
        preferences.closeTabConfirmation = .always
        preferences.confirmClosingLastPane = true
        preferences.windowStartupBehavior = .fullscreen
        preferences.showStatusBar = true
        preferences.showPressedKeyToast = false
        preferences.autocompleteEnabled = true
        preferences.agentSleepPreventionMode = .allowSleep
        preferences.attentionUnreadOnly = false
        preferences.showTabUptime = false
        preferences.autoNameAgentTabs = true
        preferences.paneTeamPointersEnabled = true
        preferences.remoteAccessEnabled = false
        preferences.inactivePaneDimming = 0.6
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )

        #expect(contents.contains("analytics = false"))
        #expect(contents.contains("language = \"english\""))
        #expect(contents.contains("on-launch = \"restore-last-session\""))
        #expect(
            contents.contains(
                "confirmation.close-window = \"when-process-running\""
            )
        )
        #expect(contents.contains("confirmation.close-tab = \"always\""))
        #expect(
            contents.contains("confirmation.close-last-pane = \"true\"")
        )
        #expect(contents.contains("window.mode = \"fullscreen\""))
        #expect(contents.contains("show-status-bar = \"true\""))
        #expect(!contents.contains("recording.show-keys"))
        #expect(contents.contains("input.show-key-toast = \"false\""))
        #expect(contents.contains("autocomplete.enabled = \"true\""))
        #expect(
            contents.contains(
                "agents.prevent-system-sleep = \"allow-sleep\""
            )
        )
        #expect(contents.contains("attention.unread-only = \"false\""))
        #expect(contents.contains("tab.show-uptime = \"false\""))
        #expect(contents.contains("tab.auto-name-agent-tabs = \"true\""))
        #expect(contents.contains("agents.pane-team-pointers = \"true\""))
        #expect(contents.contains("remote.access-enabled = \"false\""))
        #expect(contents.contains("pane.inactive-dimming = \"0.6\""))
        #expect(try store.load(from: harness.appConfiguration) == preferences)
    }

    @Test("round trips the muted push kinds and providers, defaulting to empty")
    func remotePushMutedFilters() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.remotePushMutedKinds.isEmpty)
        #expect(preferences.remotePushMutedProviders.isEmpty)

        preferences.remotePushMutedKinds = [.completion, .failure]
        preferences.remotePushMutedProviders = [.cursor, .codex]
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(
            contents.contains(
                "remote.push-muted-kinds = \"completion,failure\""
            )
        )
        #expect(
            contents.contains(
                "remote.push-muted-providers = \"codex,cursor\""
            )
        )
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        preferences.remotePushMutedKinds = []
        preferences.remotePushMutedProviders = []
        try store.save(preferences, to: harness.appConfiguration)
        let clearedContents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(clearedContents.contains("remote.push-muted-kinds = \"\""))
        #expect(clearedContents.contains("remote.push-muted-providers = \"\""))
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        try """
        remote.push-muted-kinds = "completion,not-a-kind"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }

        try """
        remote.push-muted-providers = "codex,not-a-provider"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("migrates the legacy recording key setting to the unified setting")
    func legacyRecordingKeyPreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        recording.show-keys = "true"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        let preferences = try store.load(from: harness.appConfiguration)

        #expect(preferences.showPressedKeyToast)

        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(!contents.contains("recording.show-keys"))
        #expect(contents.contains("input.show-key-toast = \"true\""))
    }

    @Test("migrates the legacy boolean sleep prevention setting to a mode")
    func legacySleepPreventionBooleanPreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        agents.prevent-system-sleep = "true"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        let preferences = try store.load(from: harness.appConfiguration)

        #expect(
            preferences.agentSleepPreventionMode == .preventWhileProcessing
        )

        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(
            contents.contains(
                "agents.prevent-system-sleep = \"prevent-while-processing\""
            )
        )
    }

    @Test("prefers the unified key setting over the legacy recording key")
    func unifiedKeyPreferencePrecedence() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        recording.show-keys = "true"
        input.show-key-toast = "false"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )

        let preferences = try ApplicationPreferencesStore().load(
            from: harness.appConfiguration
        )

        #expect(!preferences.showPressedKeyToast)
    }

    @Test("uses conservative defaults and confirmation policies")
    func applicationBehaviorDefaults() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let preferences = try ApplicationPreferencesStore().load(
            from: harness.appConfiguration
        )

        #expect(preferences.language == .systemDefault)
        #expect(preferences.launchBehavior == .restoreLastSession)
        #expect(
            preferences.closeWindowConfirmation == .whenProcessRunning
        )
        #expect(preferences.closePaneConfirmation == .whenProcessRunning)
        #expect(preferences.closeTabConfirmation == .whenProcessRunning)
        #expect(preferences.confirmClosingLastPane)
        #expect(preferences.windowStartupBehavior == .rememberLastSize)
        #expect(preferences.showStatusBar)
        #expect(!preferences.showPressedKeyToast)
        #expect(preferences.autocompleteEnabled)
        #expect(preferences.agentSleepPreventionMode == .allowSleep)
        #expect(!preferences.attentionUnreadOnly)
        #expect(!preferences.showTabUptime)
        #expect(preferences.autoNameAgentTabs)
        #expect(preferences.paneTeamPointersEnabled)
        #expect(!preferences.outerSplitOnHold)
        #expect(preferences.inactivePaneDimming == 0.32)
        #expect(preferences.activePaneBorderEnabled)
        #expect(preferences.activePaneBorderWidth == 2)
        #expect(preferences.activePaneBorderColorHex.isEmpty)
        #expect(preferences.agentContextWarningEnabled)
        #expect(preferences.agentContextWarningThreshold == 30)
        #expect(
            !CloseConfirmation.whenProcessRunning.requiresConfirmation(
                hasRunningProcess: false
            )
        )
        #expect(
            CloseConfirmation.whenProcessRunning.requiresConfirmation(
                hasRunningProcess: true
            )
        )
        #expect(
            CloseConfirmation.always.requiresConfirmation(
                hasRunningProcess: false
            )
        )
    }

    @Test("round trips the active pane border and rejects malformed values")
    func activePaneBorderPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        pane.active-border = "false"
        pane.active-border-width = "3.5"
        pane.active-border-color = "ff8800"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(!preferences.activePaneBorderEnabled)
        #expect(preferences.activePaneBorderWidth == 3.5)
        // Stored lower case, normalized on the way in.
        #expect(preferences.activePaneBorderColorHex == "FF8800")

        preferences.activePaneBorderEnabled = true
        preferences.activePaneBorderWidth = 1
        preferences.activePaneBorderColorHex = ""
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("pane.active-border = \"true\""))
        #expect(contents.contains("pane.active-border-width = \"1\""))
        #expect(contents.contains("pane.active-border-color = \"\""))

        // An empty color means "follow the accent color" and survives a
        // round trip.
        let reloaded = try store.load(from: harness.appConfiguration)
        #expect(reloaded.activePaneBorderColorHex.isEmpty)
        #expect(reloaded.activePaneBorderWidth == 1)

        var invalid = ApplicationPreferences()
        invalid.activePaneBorderWidth = 100
        #expect(throws: PreferencesStoreError.self) {
            try store.save(invalid, to: harness.appConfiguration)
        }
        invalid = ApplicationPreferences()
        invalid.activePaneBorderColorHex = "12345"
        #expect(throws: PreferencesStoreError.self) {
            try store.save(invalid, to: harness.appConfiguration)
        }

        for bad in ["pane.active-border-color = \"zzzzzz\"",
                    "pane.active-border-width = \"0\"",
                    "pane.active-border = \"sometimes\""] {
            try bad.appending("\n").write(
                to: harness.appConfiguration,
                atomically: true,
                encoding: .utf8
            )
            #expect(throws: PreferencesStoreError.self) {
                try store.load(from: harness.appConfiguration)
            }
        }
    }

    @Test("round trips the per-pane status bar and rejects malformed values")
    func paneStatusBarPreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        #expect(ApplicationPreferences().showPaneStatusBar)

        try """
        pane.status-bar = "false"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(!preferences.showPaneStatusBar)

        preferences.showPaneStatusBar = true
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("pane.status-bar = \"true\""))
        #expect(try store.load(from: harness.appConfiguration).showPaneStatusBar)

        try "pane.status-bar = \"sometimes\"\n".write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("round trips the recording fade-out and rejects malformed values")
    func recordingFadeOutPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }

        let defaults = ApplicationPreferences()
        #expect(defaults.recordingFadeOutEnabled)
        #expect(defaults.recordingFadeOutDuration == 0.5)
        #expect(defaults.recordingFadeOutColorHex == "000000")

        try """
        recording.fade-out = "false"
        recording.fade-out-duration = "1.5"
        recording.fade-out-color = "ff8800"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(!preferences.recordingFadeOutEnabled)
        #expect(preferences.recordingFadeOutDuration == 1.5)
        // Stored lower case, normalized on the way in.
        #expect(preferences.recordingFadeOutColorHex == "FF8800")

        preferences.recordingFadeOutEnabled = true
        preferences.recordingFadeOutDuration = 0.8
        preferences.recordingFadeOutColorHex = "112233"
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("recording.fade-out = \"true\""))
        #expect(contents.contains("recording.fade-out-duration = \"0.8\""))
        #expect(contents.contains("recording.fade-out-color = \"112233\""))

        let reloaded = try store.load(from: harness.appConfiguration)
        #expect(reloaded.recordingFadeOutEnabled)
        #expect(reloaded.recordingFadeOutDuration == 0.8)
        #expect(reloaded.recordingFadeOutColorHex == "112233")

        var invalid = ApplicationPreferences()
        invalid.recordingFadeOutDuration = 100
        #expect(throws: PreferencesStoreError.self) {
            try store.save(invalid, to: harness.appConfiguration)
        }
        invalid = ApplicationPreferences()
        invalid.recordingFadeOutColorHex = ""
        #expect(throws: PreferencesStoreError.self) {
            try store.save(invalid, to: harness.appConfiguration)
        }

        for bad in ["recording.fade-out-color = \"zzzzzz\"",
                    "recording.fade-out-duration = \"0\"",
                    "recording.fade-out = \"sometimes\""] {
            try bad.appending("\n").write(
                to: harness.appConfiguration,
                atomically: true,
                encoding: .utf8
            )
            #expect(throws: PreferencesStoreError.self) {
                try store.load(from: harness.appConfiguration)
            }
        }
    }

    @Test("round trips the low context warning settings")
    func agentContextWarningPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.agentContextWarningEnabled)
        #expect(preferences.agentContextWarningThreshold == 30)

        preferences.agentContextWarningEnabled = false
        preferences.agentContextWarningThreshold = 45
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("agents.context-warning = \"false\""))
        #expect(
            contents.contains("agents.context-warning-threshold = \"45\"")
        )
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        var invalid = ApplicationPreferences()
        invalid.agentContextWarningThreshold = 120
        #expect(throws: PreferencesStoreError.self) {
            try store.save(invalid, to: harness.appConfiguration)
        }

        for bad in ["agents.context-warning = \"maybe\"",
                    "agents.context-warning-threshold = \"3\"",
                    "agents.context-warning-threshold = \"high\""] {
            try bad.appending("\n").write(
                to: harness.appConfiguration,
                atomically: true,
                encoding: .utf8
            )
            #expect(throws: PreferencesStoreError.self) {
                try store.load(from: harness.appConfiguration)
            }
        }
    }

    @Test("round trips the agent meter display setting")
    func agentMeterDisplayPreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.agentMeterDisplay == .remaining)

        preferences.agentMeterDisplay = .used
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("agents.meter-display = \"used\""))
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        try "agents.meter-display = \"both\"\n".write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("round trips the recording countdown setting")
    func recordingCountdownPreference() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = ApplicationPreferencesStore()

        var preferences = try store.load(from: harness.appConfiguration)
        #expect(preferences.recordingCountdownEnabled)

        preferences.recordingCountdownEnabled = false
        try store.save(preferences, to: harness.appConfiguration)
        let contents = try String(
            contentsOf: harness.appConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("recording.countdown = \"false\""))
        #expect(try store.load(from: harness.appConfiguration) == preferences)

        try """
        recording.countdown = "maybe"
        """.appending("\n").write(
            to: harness.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: PreferencesStoreError.self) {
            try store.load(from: harness.appConfiguration)
        }
    }

    @Test("loads and saves managed Ghostty settings without replacing unknown keys")
    func terminalPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        # Keep custom key bindings.
        keybind = ctrl+shift+r=reload_config
        font-family = "JetBrains Mono"
        font-size = 15.5
        cursor-style = bar
        cursor-style-blink = false
        window-theme = dark
        foreground = E5E7EB
        background = 111827
        background-opacity = 0.82
        command = /bin/zsh
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = TerminalPreferencesStore()

        var preferences = try store.load(from: harness.terminalConfiguration)
        #expect(preferences.fontFamily == "JetBrains Mono")
        #expect(preferences.fontSize == 15.5)
        #expect(preferences.cursorStyle == .bar)
        #expect(preferences.cursorBlink == .disabled)
        #expect(preferences.appearance == .dark)
        #expect(preferences.foregroundHex == "E5E7EB")
        #expect(preferences.backgroundHex == "111827")
        #expect(preferences.backgroundOpacity == 0.82)
        #expect(preferences.shell == "/bin/zsh")

        preferences.fontSize = 17
        preferences.cursorStyle = .underline
        preferences.backgroundOpacity = 0.7
        try store.save(preferences, to: harness.terminalConfiguration)
        let contents = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )

        #expect(contents.contains("# Keep custom key bindings."))
        #expect(contents.contains("keybind = ctrl+shift+r=reload_config"))
        #expect(contents.contains("font-size = 17"))
        #expect(contents.contains("cursor-style = underline"))
        #expect(contents.contains("background-opacity = 0.7"))
        #expect(contents.components(separatedBy: "font-size").count == 2)
        #expect(try store.load(from: harness.terminalConfiguration) == preferences)
    }

    private static let japaneseCodepointMapLine =
        "font-codepoint-map = U+3000-U+303F,U+3040-U+309F,U+30A0-U+30FF,"
            + "U+31F0-U+31FF,U+3400-U+4DBF,U+4E00-U+9FFF,U+F900-U+FAFF,"
            + "U+FF00-U+FFEF=Hiragino Sans"

    @Test("save writes a single font-family line and leaves codepoint-map alone")
    func japaneseFallbackOnSave() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let store = TerminalPreferencesStore()
        var preferences = TerminalPreferences()
        preferences.fontFamily = "JetBrains Mono NL"
        try store.save(preferences, to: harness.terminalConfiguration)

        let contents = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        let lines = contents.components(separatedBy: "\n")
        let fontLines = lines.filter { $0.hasPrefix("font-family") }
        #expect(fontLines == ["font-family = \"JetBrains Mono NL\""])
        #expect(!contents.contains("font-codepoint-map"))
        let loaded = try store.load(from: harness.terminalConfiguration)
        #expect(loaded.fontFamily == "JetBrains Mono NL")

        // Saving again with the same font doesn't duplicate the line, and
        // an existing codepoint-map elsewhere in the file survives the
        // save untouched (save only owns font-family, not codepoint-map).
        try Self.japaneseCodepointMapLine.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try store.save(preferences, to: harness.terminalConfiguration)
        let rewritten = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        #expect(
            rewritten.components(separatedBy: "font-family").count == 2
        )
        #expect(rewritten.contains(Self.japaneseCodepointMapLine))
        #expect(
            rewritten.components(separatedBy: "font-codepoint-map").count
                == 2
        )
    }

    @Test("launch adds the codepoint-map fallback after a user's single font")
    func japaneseCodepointMapOnLaunch() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        font-family = "JetBrains Mono"
        font-size = 14
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let lines = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        ).components(separatedBy: "\n")

        // The primary font is untouched; the codepoint-map line lands
        // directly after it.
        let fontIndex = lines.firstIndex(where: {
            $0.hasPrefix("font-family")
        })
        #expect(fontIndex != nil)
        #expect(lines[fontIndex!] == "font-family = \"JetBrains Mono\"")
        #expect(lines[fontIndex! + 1] == Self.japaneseCodepointMapLine)
        #expect(
            lines.filter { $0.hasPrefix("font-family") }.count == 1
        )
        #expect(
            lines.filter { $0.hasPrefix("font-codepoint-map") }.count == 1
        )

        // Idempotent: a second launch doesn't add another codepoint-map.
        let prepared = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        #expect(
            try String(
                contentsOf: harness.terminalConfiguration,
                encoding: .utf8
            ) == prepared
        )
    }

    @Test("launch keeps a user's own fallback font chain untouched")
    func japaneseFallbackRespectsUserChain() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let original = """
        font-family = "JetBrains Mono"
        font-family = "UDEV Gothic NF"
        """
        try original.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let contents = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains("font-family = \"JetBrains Mono\""))
        #expect(contents.contains("UDEV Gothic NF"))
        // 3+ font-family entries are a deliberate user chain: no migration.
        #expect(
            contents.components(separatedBy: "font-family").count == 3
        )
        // The codepoint-map ensure still applies independently.
        #expect(contents.contains(Self.japaneseCodepointMapLine))
    }

    @Test("launch migrates the old two-line Hiragino fallback to a codepoint-map")
    func japaneseFallbackMigratesOldTwoLineFallback() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        font-family = "JetBrains Mono"
        font-family = "Hiragino Sans"
        font-size = 14
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let lines = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        ).components(separatedBy: "\n")

        // The second font-family line is gone; the primary is untouched
        // and the codepoint-map takes its place as the Japanese fallback.
        #expect(
            lines.filter { $0.hasPrefix("font-family") }
                == ["font-family = \"JetBrains Mono\""]
        )
        #expect(
            lines.filter { $0.hasPrefix("font-codepoint-map") }
                == [Self.japaneseCodepointMapLine]
        )
    }

    @Test("launch leaves a three-entry font-family chain alone beyond the codepoint-map ensure")
    func japaneseFallbackLeavesThreeEntryChainAlone() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        font-family = "JetBrains Mono"
        font-family = "UDEV Gothic NF"
        font-family = "Hiragino Sans"
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let lines = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        ).components(separatedBy: "\n")

        #expect(
            lines.filter { $0.hasPrefix("font-family") } == [
                "font-family = \"JetBrains Mono\"",
                "font-family = \"UDEV Gothic NF\"",
                "font-family = \"Hiragino Sans\"",
            ]
        )
        #expect(
            lines.filter { $0.hasPrefix("font-codepoint-map") }
                == [Self.japaneseCodepointMapLine]
        )
    }

    @Test("launch keeps a user-chosen Hiragino primary and still ensures the codepoint-map")
    func japaneseFallbackKeepsHiraginoAsChosenPrimary() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        font-family = "Hiragino Sans"
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let lines = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        ).components(separatedBy: "\n")

        #expect(
            lines.filter { $0.hasPrefix("font-family") }
                == ["font-family = \"Hiragino Sans\""]
        )
        #expect(
            lines.filter { $0.hasPrefix("font-codepoint-map") }
                == [Self.japaneseCodepointMapLine]
        )
    }

    @Test("launch ensures the codepoint-map even with no font-family at all")
    func japaneseFallbackEnsuredWithNoFontFamily() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        font-size = 14
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let contents = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        #expect(!contents.contains("font-family"))
        #expect(contents.contains(Self.japaneseCodepointMapLine))
    }

    @Test("launch adds our codepoint-map alongside a user's unrelated one")
    func japaneseFallbackAddsAlongsideUserCodepointMap() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        font-family = "JetBrains Mono"
        font-codepoint-map = U+E000-U+F8FF=SomeNerdFont
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let lines = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        ).components(separatedBy: "\n")

        let codepointMapLines = lines.filter {
            $0.hasPrefix("font-codepoint-map")
        }
        #expect(codepointMapLines.count == 2)
        #expect(
            codepointMapLines.contains(
                "font-codepoint-map = U+E000-U+F8FF=SomeNerdFont"
            )
        )
        #expect(codepointMapLines.contains(Self.japaneseCodepointMapLine))
    }

    @Test("launch is a true no-op (no write) when everything is already prepared")
    func japaneseFallbackAlreadyPreparedIsNoWrite() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        shell-integration-features = no-cursor
        font-feature = -calt, -liga, -dlig
        font-family = "JetBrains Mono"
        \(Self.japaneseCodepointMapLine)
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let before = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )

        // Make the file unwritable: if prepareForLaunch attempted a write
        // it would throw, proving the guard's early return actually skips
        // the write rather than merely reproducing the same bytes.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: harness.terminalConfiguration.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: harness.terminalConfiguration.path
            )
        }

        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )

        let after = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        #expect(after == before)
    }

    @Test("uses Ghostty-compatible defaults for empty configuration")
    func defaults() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let terminal = try TerminalPreferencesStore().load(
            from: harness.terminalConfiguration
        )
        let application = try ApplicationPreferencesStore().load(
            from: harness.appConfiguration
        )

        #expect(application == ApplicationPreferences())
        #expect(terminal == TerminalPreferences())
        #expect(terminal.fontSize == 13)
        #expect(terminal.cursorBlink == .system)
        #expect(terminal.foregroundHex == "FFFFFF")
        #expect(terminal.backgroundHex == "282C34")
    }

    @Test("writes a Ghostty theme without custom color overrides")
    func terminalTheme() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        theme = light:3024 Day,dark:3024 Night
        foreground = E5E7EB
        background = 111827
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = TerminalPreferencesStore()

        var preferences = try store.load(from: harness.terminalConfiguration)
        #expect(preferences.theme == "light:3024 Day,dark:3024 Night")

        try store.save(preferences, to: harness.terminalConfiguration)
        var contents = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        #expect(contents.contains(
            "theme = light:3024 Day,dark:3024 Night"
        ))
        #expect(!contents.contains("foreground ="))
        #expect(!contents.contains("background ="))

        preferences.theme = ""
        preferences.foregroundHex = "ABCDEF"
        preferences.backgroundHex = "123456"
        try store.save(preferences, to: harness.terminalConfiguration)
        contents = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        #expect(!contents.components(separatedBy: .newlines).contains {
            $0.hasPrefix("theme =")
        })
        #expect(contents.contains("foreground = ABCDEF"))
        #expect(contents.contains("background = 123456"))
    }

    @Test("disables only the shell-integrated prompt cursor before launch")
    func preparesCursorStyleForLaunch() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        shell-integration-features = sudo,no-title,cursor
        keybind = ctrl+shift+r=reload_config
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = TerminalPreferencesStore()

        try store.prepareForLaunch(at: harness.terminalConfiguration)
        let prepared = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )

        #expect(prepared.contains(
            "shell-integration-features = sudo,no-title,no-cursor"
        ))
        #expect(prepared.contains("keybind = ctrl+shift+r=reload_config"))
        // Ligatures are disabled by default when the user set no font-feature.
        #expect(prepared.contains("font-feature = -calt, -liga, -dlig"))
        #expect(
            prepared.components(
                separatedBy: "shell-integration-features"
            ).count == 2
        )

        try store.prepareForLaunch(at: harness.terminalConfiguration)
        #expect(
            try String(
                contentsOf: harness.terminalConfiguration,
                encoding: .utf8
            ) == prepared
        )
    }

    @Test("adds the ligature default even when the cursor is already disabled")
    func addsLigatureDefaultWithCursorAlreadyDisabled() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        # Managed by mytty Settings: terminal
        font-family = "JetBrainsMono Nerd Font Mono"
        shell-integration-features = no-cursor
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
        let store = TerminalPreferencesStore()

        try store.prepareForLaunch(at: harness.terminalConfiguration)
        let prepared = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )
        #expect(prepared.contains("font-feature = -calt, -liga, -dlig"))
        #expect(prepared.contains("shell-integration-features = no-cursor"))
        #expect(prepared.contains("font-family = \"JetBrainsMono Nerd Font Mono\""))

        // Idempotent: a second launch adds no second font-feature.
        try store.prepareForLaunch(at: harness.terminalConfiguration)
        #expect(
            try String(
                contentsOf: harness.terminalConfiguration,
                encoding: .utf8
            ).components(separatedBy: "font-feature").count == 2
        )
    }

    @Test("keeps a user's own font-feature instead of forcing ligatures off")
    func preservesUserFontFeature() throws {
        let harness = try Harness()
        defer { harness.remove() }
        try """
        shell-integration-features = no-cursor
        font-feature = calt
        """.appending("\n").write(
            to: harness.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )

        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )
        let prepared = try String(
            contentsOf: harness.terminalConfiguration,
            encoding: .utf8
        )

        #expect(prepared.contains("font-feature = calt"))
        #expect(!prepared.contains("-calt"))
    }

    @Test("disables the prompt cursor and ligatures in an empty config")
    func preparesEmptyTerminalConfiguration() throws {
        let harness = try Harness()
        defer { harness.remove() }

        try TerminalPreferencesStore().prepareForLaunch(
            at: harness.terminalConfiguration
        )

        #expect(
            try String(
                contentsOf: harness.terminalConfiguration,
                encoding: .utf8
            ) == """
            shell-integration-features = no-cursor
            font-feature = -calt, -liga, -dlig
            \(Self.japaneseCodepointMapLine)

            """
        )
    }
}

private struct Harness {
    let root: URL
    let appConfiguration: URL
    let terminalConfiguration: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        appConfiguration = root.appendingPathComponent("config.toml")
        terminalConfiguration = root.appendingPathComponent("terminal.conf")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data().write(to: appConfiguration)
        try Data().write(to: terminalConfiguration)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
