import Foundation
import MyTTYRemoteKit

enum RemotePairingRejection: Equatable {
    case noActiveCode
    case codeExpired
    case codeMismatch
}

enum RemotePairingAttemptResult: Equatable {
    case approved(RemotePairedDevice)
    case rejected(RemotePairingRejection)
}

/// Owns the lifecycle of the six digit pairing code shown in Settings.
/// A code is single-use: the first attempt against it (successful or not)
/// consumes it, and a new code must be generated to retry.
@MainActor
final class RemotePairingCoordinator {
    private(set) var activeCode: RemotePairingCode?
    private let deviceStore: RemotePairedDeviceStore
    private let now: () -> Date

    init(
        deviceStore: RemotePairedDeviceStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.deviceStore = deviceStore
        self.now = now
    }

    @discardableResult
    func beginPairing() -> RemotePairingCode {
        let code = RemotePairing.generateCode(generatedAt: now())
        activeCode = code
        return code
    }

    func cancelPairing() {
        activeCode = nil
    }

    @discardableResult
    func attempt(
        code: String,
        deviceName: String
    ) throws -> RemotePairingAttemptResult {
        guard let active = activeCode else {
            return .rejected(.noActiveCode)
        }
        activeCode = nil

        guard !active.isExpired(at: now()) else {
            return .rejected(.codeExpired)
        }
        guard active.value == code else {
            return .rejected(.codeMismatch)
        }

        let device = RemotePairedDevice(
            id: RemotePairing.generateDeviceID(),
            name: deviceName,
            secretBase64: RemotePairing.generateDeviceSecret()
                .base64EncodedString(),
            // Rounded to whole seconds: converting through the store's
            // 1970-epoch JSON encoding does not round-trip sub-second
            // precision bit-for-bit (Date is stored relative to a 2001
            // reference date internally), and nothing here needs finer
            // granularity than a second.
            pairedAt: Date(
                timeIntervalSince1970: now().timeIntervalSince1970.rounded()
            )
        )
        try deviceStore.add(device)
        return .approved(device)
    }
}
