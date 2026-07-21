import Darwin
import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent event socket client error descriptions")
struct AgentEventSocketClientErrorTests {
    @Test("EPERM gets a sandbox-specific message for the hook binary")
    func socketOperationEPERMMessage() {
        let description =
            "\(AgentEventSocketClientError.socketOperation(EPERM))"
        #expect(description.contains("sandbox"))
        #expect(description.contains("EPERM"))
        #expect(!description.contains("socketOperation(\(EPERM))"))
    }

    @Test("Other errno values keep the raw code and add strerror text")
    func socketOperationOtherErrnoMessage() {
        let description =
            "\(AgentEventSocketClientError.socketOperation(ECONNRESET))"
        #expect(description.contains("\(ECONNRESET)"))
        #expect(
            description.contains(String(cString: strerror(ECONNRESET)))
        )
        #expect(!description.contains("sandbox"))
    }

    @Test("Non-socketOperation cases are unaffected by the new description")
    func otherCasesDescription() {
        #expect(
            "\(AgentEventSocketClientError.socketPathTooLong)"
                == "socketPathTooLong"
        )
        #expect(
            "\(AgentEventSocketClientError.emptyResponse)" == "emptyResponse"
        )
        #expect(
            "\(AgentEventSocketClientError.responseTooLarge)"
                == "responseTooLarge"
        )
        #expect(
            "\(AgentEventSocketClientError.invalidResponse)"
                == "invalidResponse"
        )
    }
}
