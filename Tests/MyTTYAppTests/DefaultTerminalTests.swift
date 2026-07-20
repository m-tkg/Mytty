import Foundation
import Testing

@testable import MyTTYApp

@Suite("Default terminal")
struct DefaultTerminalTests {
    @Test("reports whether Mytty owns Unix executable files")
    @MainActor
    func refreshesOwnership() {
        let applicationURL = URL(fileURLWithPath: "/Applications/Mytty.app")
        let registrar = StubDefaultTerminalRegistrar(
            currentApplicationURL: applicationURL
        )
        let model = DefaultTerminalModel(
            applicationURL: applicationURL,
            registrar: registrar
        )

        model.refresh()

        #expect(model.isDefault)
        #expect(!model.isUpdating)
        #expect(model.failure == nil)

        registrar.currentApplicationURL = URL(
            fileURLWithPath: "/Applications/Other.app"
        )
        model.refresh()

        #expect(!model.isDefault)
    }

    @Test("registers Mytty and refreshes ownership")
    @MainActor
    func registersApplication() async {
        let applicationURL = URL(fileURLWithPath: "/Applications/Mytty.app")
        let registrar = StubDefaultTerminalRegistrar(currentApplicationURL: nil)
        registrar.applicationURLAfterRegistration = applicationURL
        let model = DefaultTerminalModel(
            applicationURL: applicationURL,
            registrar: registrar
        )

        await model.makeDefault()

        #expect(registrar.registeredApplicationURLs == [applicationURL])
        #expect(model.isDefault)
        #expect(!model.isUpdating)
        #expect(model.failure == nil)
    }

    @Test("publishes a registration failure without claiming ownership")
    @MainActor
    func reportsFailure() async {
        let applicationURL = URL(fileURLWithPath: "/Applications/Mytty.app")
        let registrar = StubDefaultTerminalRegistrar(currentApplicationURL: nil)
        registrar.error = TestError.registrationFailed
        let model = DefaultTerminalModel(
            applicationURL: applicationURL,
            registrar: registrar
        )

        await model.makeDefault()

        #expect(!model.isDefault)
        #expect(!model.isUpdating)
        #expect(model.failure == .registration)
    }
}

@MainActor
private final class StubDefaultTerminalRegistrar: DefaultTerminalRegistering {
    var currentApplicationURL: URL?
    var applicationURLAfterRegistration: URL?
    var error: Error?
    private(set) var registeredApplicationURLs: [URL] = []

    init(currentApplicationURL: URL?) {
        self.currentApplicationURL = currentApplicationURL
    }

    func defaultApplicationURL() -> URL? {
        currentApplicationURL
    }

    func setDefaultApplication(at applicationURL: URL) async throws {
        registeredApplicationURLs.append(applicationURL)
        if let error {
            throw error
        }
        currentApplicationURL = applicationURLAfterRegistration
    }
}

private enum TestError: Error {
    case registrationFailed
}
