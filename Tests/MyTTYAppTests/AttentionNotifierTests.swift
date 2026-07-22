import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Attention notification body")
struct AttentionNotifierTests {
    private static let surfaceID = TerminalSurfaceID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000201"
    )!)

    @Test("localizes an approval request's body from its structured tool name")
    func approvalRequestUsesLocalizedToolName() {
        let item = Self.makeItem(kind: .approvalRequested, toolName: "Bash")

        #expect(
            item.notificationBody(localizer: MyTTYLocalizer(language: .english))
                == "Bash requires approval"
        )
        #expect(
            item.notificationBody(localizer: MyTTYLocalizer(language: .japanese))
                == "Bash の承認が必要です"
        )
    }

    @Test("localizes an input request's body from its structured tool name")
    func inputRequestUsesLocalizedToolName() {
        let item = Self.makeItem(kind: .inputRequested, toolName: "AskUserQuestion")

        #expect(
            item.notificationBody(localizer: MyTTYLocalizer(language: .english))
                == "AskUserQuestion requests input"
        )
        #expect(
            item.notificationBody(localizer: MyTTYLocalizer(language: .japanese))
                == "AskUserQuestion が入力を求めています"
        )
    }

    @Test("falls back to the generic body when no tool name is known")
    func approvalRequestWithoutToolNameFallsBack() {
        let english = MyTTYLocalizer(language: .english)
        let item = Self.makeItem(kind: .approvalRequested, toolName: nil)

        #expect(
            item.notificationBody(localizer: english)
                == AttentionItemKind.approvalRequest.notificationBody(localizer: english)
        )
    }

    @Test("keeps showing the event's own message for failures and completions")
    func failureAndCompletionKeepTheirOwnMessage() {
        let english = MyTTYLocalizer(language: .english)
        let failure = Self.makeItem(
            kind: .failed,
            toolName: "Bash",
            message: "Command exited 1"
        )
        let completionWithoutMessage = Self.makeItem(
            kind: .succeeded,
            toolName: nil,
            message: nil
        )

        #expect(failure.notificationBody(localizer: english) == "Command exited 1")
        #expect(
            completionWithoutMessage.notificationBody(localizer: english)
                == AttentionItemKind.completion.notificationBody(localizer: english)
        )
    }

    private static func makeItem(
        kind: AgentEventKind,
        toolName: String?,
        message: String? = nil
    ) -> AttentionItem {
        let runID = AgentRunID(rawValue: UUID())
        let started = AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: .started,
            occurredAt: Date(timeIntervalSince1970: 0)
        )
        let requestEvent = AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: kind,
            occurredAt: Date(timeIntervalSince1970: 1),
            message: message,
            toolName: toolName
        )

        let items = AttentionReducer.reduce(
            events: [started, requestEvent],
            acknowledgements: [],
            now: Date(timeIntervalSince1970: 2)
        )
        return items[0]
    }
}
