import Foundation
import Testing

@testable import MyTTYApp

@MainActor
@Suite("Remote pairing coordinator")
struct RemotePairingCoordinatorTests {
    @Test("attempting without an active code is rejected")
    func attemptWithoutActiveCodeIsRejected() throws {
        let coordinator = try makeCoordinator()
        let result = try coordinator.attempt(code: "123456", deviceName: "iPhone")
        #expect(result == .rejected(.noActiveCode))
    }

    @Test("a matching code approves and persists a new device")
    func matchingCodeApproves() throws {
        let store = try makeStore()
        let coordinator = RemotePairingCoordinator(deviceStore: store)
        let code = coordinator.beginPairing()

        let result = try coordinator.attempt(code: code.value, deviceName: "iPhone")
        guard case let .approved(device) = result else {
            Issue.record("expected approval")
            return
        }
        #expect(device.name == "iPhone")
        #expect(try store.load() == [device])
    }

    @Test("a code is single-use even when the attempt matches")
    func codeIsConsumedAfterFirstAttempt() throws {
        let coordinator = try makeCoordinator()
        let code = coordinator.beginPairing()

        _ = try coordinator.attempt(code: code.value, deviceName: "iPhone")
        let second = try coordinator.attempt(code: code.value, deviceName: "iPad")

        #expect(second == .rejected(.noActiveCode))
    }

    @Test("a mismatched code is rejected and consumes the active code")
    func mismatchedCodeIsRejected() throws {
        let coordinator = try makeCoordinator()
        let code = coordinator.beginPairing()
        _ = code

        let result = try coordinator.attempt(code: "000000", deviceName: "iPhone")
        #expect(result == .rejected(.codeMismatch))

        let retry = try coordinator.attempt(code: code.value, deviceName: "iPhone")
        #expect(retry == .rejected(.noActiveCode))
    }

    @Test("an expired code is rejected even if the value matches")
    func expiredCodeIsRejected() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let coordinator = RemotePairingCoordinator(
            deviceStore: try makeStore(),
            now: { now }
        )
        let code = coordinator.beginPairing()
        now = code.expiresAt

        let result = try coordinator.attempt(code: code.value, deviceName: "iPhone")
        #expect(result == .rejected(.codeExpired))
    }

    @Test("cancelling pairing clears the active code")
    func cancelClearsActiveCode() throws {
        let coordinator = try makeCoordinator()
        _ = coordinator.beginPairing()
        coordinator.cancelPairing()

        let result = try coordinator.attempt(code: "123456", deviceName: "iPhone")
        #expect(result == .rejected(.noActiveCode))
    }

    @Test("beginning pairing again replaces the previous code")
    func beginPairingReplacesPreviousCode() throws {
        let coordinator = try makeCoordinator()
        let first = coordinator.beginPairing()
        let second = coordinator.beginPairing()

        let usingFirst = try coordinator.attempt(
            code: first.value,
            deviceName: "iPhone"
        )
        if first.value == second.value {
            #expect(usingFirst != .rejected(.noActiveCode))
        } else {
            #expect(usingFirst == .rejected(.codeMismatch))
        }
    }

    private func makeStore() throws -> RemotePairedDeviceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("remote-devices.json", isDirectory: false)
        return RemotePairedDeviceStore(fileURL: fileURL)
    }

    private func makeCoordinator() throws -> RemotePairingCoordinator {
        RemotePairingCoordinator(deviceStore: try makeStore())
    }
}
