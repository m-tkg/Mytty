import Darwin
import Foundation
import Testing

@testable import MyTTYCore

@Suite("Control socket client error descriptions")
struct ControlSocketClientErrorTests {
    @Test("EPERM gets a sandbox-specific, Codex-referencing message")
    func socketOperationEPERMMessage() {
        let description = "\(ControlSocketClientError.socketOperation(EPERM))"
        #expect(description.contains("sandbox"))
        #expect(description.contains("Codex"))
        #expect(description.contains("EPERM"))
        #expect(!description.contains("socketOperation(\(EPERM))"))
    }

    @Test("Other errno values keep the raw code and add strerror text")
    func socketOperationOtherErrnoMessage() {
        let description = "\(ControlSocketClientError.socketOperation(ECONNRESET))"
        #expect(description.contains("\(ECONNRESET)"))
        #expect(
            description.contains(String(cString: strerror(ECONNRESET)))
        )
        #expect(!description.contains("sandbox"))
    }

    @Test("Non-socketOperation cases are unaffected by the new description")
    func otherCasesDescription() {
        #expect(
            "\(ControlSocketClientError.socketPathTooLong)"
                == "socketPathTooLong"
        )
        #expect(
            "\(ControlSocketClientError.emptyResponse)" == "emptyResponse"
        )
        #expect(
            "\(ControlSocketClientError.responseTooLarge)"
                == "responseTooLarge"
        )
        #expect(
            "\(ControlSocketClientError.invalidResponse)"
                == "invalidResponse"
        )
        #expect(
            "\(ControlSocketClientError.appNotRunning)" == "appNotRunning"
        )
    }

    @Test("Description still round-trips through Equatable")
    func equatableUnaffected() {
        #expect(
            ControlSocketClientError.socketOperation(EPERM)
                == ControlSocketClientError.socketOperation(EPERM)
        )
        #expect(
            ControlSocketClientError.socketOperation(EPERM)
                != ControlSocketClientError.socketOperation(ECONNRESET)
        )
    }
}
