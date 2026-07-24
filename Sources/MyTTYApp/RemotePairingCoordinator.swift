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

/// Owns the lifecycle of the high-entropy pairing token shown as a QR code
/// in Settings. A token is single-use once a guess actually reaches
/// `attempt()`: that only happens after the guess's derived key has already
/// opened the handshake frame, and `attempt()` consumes the token on that
/// first call whether the value inside the frame turns out to match or not.
/// A wrong-token guess never gets that far — the frame fails to open with
/// the real token's key before `attempt()` is reached — so those are tracked
/// separately via `recordFailedAttempt()`, which invalidates the active
/// token after `maxFailedAttempts` such guesses. Together this means a
/// guesser gets at most a handful of tries before the token dies and the
/// user has to generate a new one.
@MainActor
final class RemotePairingCoordinator {
    /// Number of failed online guesses (frames that couldn't be opened
    /// with the active code's derived key at all) tolerated against a
    /// single active code before it is invalidated.
    static let maxFailedAttempts = 5

    private(set) var activeCode: RemotePairingCode?
    private var failedAttemptCount = 0
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
        failedAttemptCount = 0
        return code
    }

    func cancelPairing() {
        activeCode = nil
        failedAttemptCount = 0
    }

    /// Records an online guess whose frame could not be opened at all
    /// using the active code's derived key (see
    /// `RemoteHandshakeResolution.pairingKeyRejected`). Once
    /// `maxFailedAttempts` accumulate against the same active code, it is
    /// invalidated, so a brute-force script cannot keep probing it for the
    /// rest of its 120s validity window. A no-op if no code is active.
    func recordFailedAttempt() {
        guard activeCode != nil else { return }
        failedAttemptCount += 1
        guard failedAttemptCount >= Self.maxFailedAttempts else { return }
        activeCode = nil
        failedAttemptCount = 0
    }

    @discardableResult
    func attempt(
        token: String,
        deviceName: String
    ) throws -> RemotePairingAttemptResult {
        guard let active = activeCode else {
            return .rejected(.noActiveCode)
        }
        activeCode = nil

        guard !active.isExpired(at: now()) else {
            return .rejected(.codeExpired)
        }
        guard active.value == token else {
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
