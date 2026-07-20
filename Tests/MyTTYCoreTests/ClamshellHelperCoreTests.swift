import Foundation
import Testing

@testable import MyTTYCore

@Suite("Clamshell helper core")
struct ClamshellHelperCoreTests {
    private final class PMSetLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Bool] = []
        var result = true

        func record(_ value: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            values.append(value)
            return result
        }

        var calls: [Bool] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    @Test("applies pmset only when the state changes")
    func appliesOnChange() {
        let log = PMSetLog()
        let core = ClamshellHelperCore(
            setDisableSleep: { log.record($0) },
            isProcessAlive: { _ in true }
        )
        #expect(core.setKeepAwake(true, watchedPID: 42))
        #expect(core.setKeepAwake(true, watchedPID: 42))
        #expect(log.calls == [true])
        #expect(core.setKeepAwake(false, watchedPID: 42))
        #expect(core.setKeepAwake(false, watchedPID: 42))
        #expect(log.calls == [true, false])
    }

    @Test("rejects enabling for a dead or invalid process")
    func rejectsDeadProcess() {
        let log = PMSetLog()
        let core = ClamshellHelperCore(
            setDisableSleep: { log.record($0) },
            isProcessAlive: { _ in false }
        )
        #expect(!core.setKeepAwake(true, watchedPID: 42))
        #expect(!core.setKeepAwake(true, watchedPID: 0))
        #expect(log.calls.isEmpty)
    }

    @Test("restores sleep when the watched process exits")
    func restoresOnWatchedExit() async throws {
        let log = PMSetLog()
        let alive = LockedBox(true)
        let core = ClamshellHelperCore(
            pollInterval: 0.05,
            setDisableSleep: { log.record($0) },
            isProcessAlive: { _ in alive.value }
        )
        #expect(core.setKeepAwake(true, watchedPID: 42))
        alive.value = false
        var restored = false
        for _ in 0..<100 {
            if log.calls == [true, false] {
                restored = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(restored)
    }

    private final class LockedBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Bool

        init(_ value: Bool) { stored = value }

        var value: Bool {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }
}
