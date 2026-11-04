import Testing

@testable import MyTTYApp

@Suite("Attention notification routing")
struct AttentionNotificationRoutingTests {
    private func route(
        suppressed: Bool = false,
        appActive: Bool = false,
        focused: Bool = false,
        visible: Bool = false
    ) -> AttentionNotificationRouting {
        AttentionNotificationRouting.decide(
            isSuppressed: suppressed,
            isAppActive: appActive,
            isActivelyFocused: focused,
            isVisible: visible
        )
    }

    @Test("a silenced agent-spawn pane never notifies or acknowledges")
    func silencedPaneIsQuiet() {
        for appActive in [false, true] {
            for focused in [false, true] {
                for visible in [false, true] {
                    let result = route(
                        suppressed: true,
                        appActive: appActive,
                        focused: focused,
                        visible: visible
                    )
                    #expect(result == .none)
                }
            }
        }
    }

    @Test("a hidden pane of an unattended Mac gets banner and phone push")
    func hiddenPaneNotifiesEverywhere() {
        #expect(route() == .init(pushToPhone: true, banner: true))
    }

    @Test("an active app only skips the phone push")
    func activeAppSkipsPush() {
        #expect(route(appActive: true) == .init(pushToPhone: false, banner: true))
    }

    @Test("a visible pane gets no banner")
    func visiblePaneNoBanner() {
        #expect(route(visible: true) == .init(pushToPhone: true, banner: false))
    }

    @Test("a focused pane acknowledges instead of notifying the Mac")
    func focusedPaneAcknowledges() {
        #expect(
            route(focused: true, visible: true)
                == .init(
                    pushToPhone: true,
                    banner: false,
                    acknowledgeItems: true
                )
        )
    }

    @Test("a --notify pane (not suppressed) follows the human-pane rules")
    func notifyPaneMatchesHumanPane() {
        #expect(route(suppressed: false) == route())
    }
}
