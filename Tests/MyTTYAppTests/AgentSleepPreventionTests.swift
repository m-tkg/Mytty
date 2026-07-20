import Foundation
import Testing

@testable import MyTTYApp

@Suite("Agent sleep prevention")
struct AgentSleepPreventionTests {
    @Test("prevents sleep once while any window has matching agent activity")
    @MainActor
    func beginsForAnyActiveWindow() {
        let token = NSObject()
        var beginCount = 0
        var endedTokens: [NSObjectProtocol] = []
        let controller = AgentSleepPreventionController(
            beginActivity: {
                beginCount += 1
                return token
            },
            endActivity: { endedTokens.append($0) }
        )

        controller.update(
            mode: .preventWhileProcessing,
            windowAgentIsActive: [false, true, false]
        )
        controller.update(
            mode: .preventWhileProcessing,
            windowAgentIsActive: [true, true]
        )

        #expect(
            controller.status
                == AgentSleepStatus(
                    mode: .preventWhileProcessing,
                    isActive: true
                )
        )
        #expect(beginCount == 1)
        #expect(endedTokens.isEmpty)
    }

    @Test("distinguishes disabled, armed, and actively prevented states")
    @MainActor
    func endsWhenNoLongerRequired() {
        let token = NSObject()
        var beginCount = 0
        var endedTokens: [NSObjectProtocol] = []
        let controller = AgentSleepPreventionController(
            beginActivity: {
                beginCount += 1
                return token
            },
            endActivity: { endedTokens.append($0) }
        )

        controller.update(
            mode: .allowSleep,
            windowAgentIsActive: [true]
        )
        #expect(controller.status == .disabled)
        #expect(beginCount == 0)

        controller.update(
            mode: .preventWhileProcessing,
            windowAgentIsActive: [false, false]
        )
        #expect(
            controller.status
                == AgentSleepStatus(
                    mode: .preventWhileProcessing,
                    isActive: false
                )
        )
        #expect(beginCount == 0)

        controller.update(
            mode: .preventWhileProcessing,
            windowAgentIsActive: [true]
        )
        controller.update(
            mode: .preventWhileProcessing,
            windowAgentIsActive: [false, false]
        )

        #expect(
            controller.status
                == AgentSleepStatus(
                    mode: .preventWhileProcessing,
                    isActive: false
                )
        )
        #expect(beginCount == 1)
        #expect(endedTokens.count == 1)
        #expect((endedTokens.first as AnyObject?) === token)
    }

    @Test("switches modes without restarting an activity that is still needed")
    @MainActor
    func switchesModeWhileActive() {
        let token = NSObject()
        var beginCount = 0
        var endedTokens: [NSObjectProtocol] = []
        let controller = AgentSleepPreventionController(
            beginActivity: {
                beginCount += 1
                return token
            },
            endActivity: { endedTokens.append($0) }
        )

        controller.update(
            mode: .preventWhileLaunched,
            windowAgentIsActive: [true]
        )
        #expect(
            controller.status
                == AgentSleepStatus(mode: .preventWhileLaunched, isActive: true)
        )

        controller.update(
            mode: .preventWhileProcessing,
            windowAgentIsActive: [true]
        )

        #expect(
            controller.status
                == AgentSleepStatus(
                    mode: .preventWhileProcessing,
                    isActive: true
                )
        )
        #expect(beginCount == 1)
        #expect(endedTokens.isEmpty)
    }

    /// Display sleep has to be held off too: with no awake display,
    /// libghostty cannot build the display link every surface's renderer
    /// is created with, so an unattended Mac would refuse to open the
    /// pane a remote or `mytty-ctl` asks for.
    @Test("holds off display sleep as well as system sleep")
    func preventsDisplaySleep() {
        #expect(
            AgentSleepPreventionController.activityOptions
                .contains(.idleSystemSleepDisabled)
        )
        #expect(
            AgentSleepPreventionController.activityOptions
                .contains(.idleDisplaySleepDisabled)
        )
    }

    @Test("the tooltip announces the clamshell state while armed")
    @MainActor
    func clamshellTooltip() {
        let localizer = MyTTYLocalizer(language: .japanese)
        var status = AgentSleepStatus(
            mode: .preventWhileProcessing,
            isActive: true
        )
        #expect(
            !status.tooltip(localizer: localizer)
                .contains("モニタを閉じてもスリープしません")
        )
        status.keepsLidClosedAwake = true
        #expect(
            status.tooltip(localizer: localizer)
                .contains("モニタを閉じてもスリープしません")
        )
    }

    @Test("provides distinct status bar presentation for every state")
    func statusPresentation() {
        #expect(
            AgentSleepStatus.disabled.text == .sleepPreventionDisabled
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileProcessing, isActive: false)
                .text == .sleepPreventionEnabled
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileProcessing, isActive: true)
                .text == .sleepPrevented
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileLaunched, isActive: false)
                .text == .sleepPreventionArmedWhileLaunched
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileLaunched, isActive: true)
                .text == .sleepPreventingWhileLaunched
        )

        #expect(AgentSleepStatus.disabled.symbolName == "moon")
        #expect(
            AgentSleepStatus(mode: .preventWhileProcessing, isActive: false)
                .symbolName == "sun.haze"
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileProcessing, isActive: true)
                .symbolName == "sun.haze.fill"
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileLaunched, isActive: false)
                .symbolName == "sun.max"
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileLaunched, isActive: true)
                .symbolName == "sun.max.fill"
        )

        #expect(
            AgentSleepStatus(mode: .preventWhileProcessing, isActive: false)
                .tooltip(localizer: MyTTYLocalizer(language: .english))
                == "Agent sleep prevention on"
        )
        #expect(
            AgentSleepStatus(mode: .preventWhileLaunched, isActive: true)
                .tooltip(localizer: MyTTYLocalizer(language: .japanese))
                == "スリープを抑止中(Agent 起動中)"
        )
    }
}
