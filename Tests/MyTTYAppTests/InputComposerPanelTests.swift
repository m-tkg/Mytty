import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Input composer panel")
struct InputComposerPanelTests {
    @MainActor
    @Test("sends the exact multi-line draft, then clears and closes")
    func sendsExactTextAndClears() {
        let localizer = MyTTYLocalizer(language: .english)
        var sent: [String] = []
        let controller = InputComposerPanelController(
            localizer: localizer
        ) { text in
            sent.append(text)
            return true
        }
        controller.show()
        controller.draftText = "line one\nline two\n"

        controller.sendCurrentText()

        #expect(sent == ["line one\nline two\n"])
        #expect(controller.draftText == "")
        #expect(controller.statusText == "")
        #expect(controller.isPanelVisible == false)
    }

    @MainActor
    @Test("keeps the draft and shows the no-pane status on a failed send")
    func failedSendKeepsDraft() {
        let localizer = MyTTYLocalizer(language: .english)
        let controller = InputComposerPanelController(
            localizer: localizer
        ) { _ in false }
        controller.show()
        controller.draftText = "still here"

        controller.sendCurrentText()

        #expect(controller.draftText == "still here")
        #expect(controller.isPanelVisible == true)
        #expect(
            controller.statusText
                == localizer[.inputComposerNoTerminalPane]
        )
    }

    @MainActor
    @Test("does not invoke send for an empty draft")
    func emptyDraftIsNoOp() {
        let localizer = MyTTYLocalizer(language: .english)
        var invocationCount = 0
        let controller = InputComposerPanelController(
            localizer: localizer
        ) { _ in
            invocationCount += 1
            return true
        }
        controller.show()
        controller.draftText = ""

        controller.sendCurrentText()

        #expect(invocationCount == 0)
    }

    @MainActor
    @Test("a later successful send clears a previous failure status")
    func successClearsPriorStatus() {
        let localizer = MyTTYLocalizer(language: .english)
        var shouldSucceed = false
        let controller = InputComposerPanelController(
            localizer: localizer
        ) { _ in shouldSucceed }
        controller.show()
        controller.draftText = "first attempt"
        controller.sendCurrentText()
        #expect(
            controller.statusText
                == localizer[.inputComposerNoTerminalPane]
        )

        shouldSucceed = true
        controller.draftText = "second attempt"
        controller.sendCurrentText()

        #expect(controller.statusText == "")
        #expect(controller.draftText == "")
    }
}
