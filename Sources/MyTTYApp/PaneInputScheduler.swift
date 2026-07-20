import Combine
import Foundation
import MyTTYCore

enum PaneInputSchedulerError: Error, Equatable {
    case pastDate
}

@MainActor
final class PaneInputScheduler: NSObject, ObservableObject {
    @Published private(set) var schedules: [PaneInputSchedule] = []

    private let repository: SQLitePaneInputScheduleRepository
    private let timerEnabled: Bool
    private let onFire: (PaneInputSchedule) -> Void
    private let onError: (Error) -> Void
    private var timer: Timer?

    init(
        repository: SQLitePaneInputScheduleRepository,
        timerEnabled: Bool = true,
        onFire: @escaping (PaneInputSchedule) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.repository = repository
        self.timerEnabled = timerEnabled
        self.onFire = onFire
        self.onError = onError
        super.init()
    }

    func reload(
        validSurfaceIDs: Set<TerminalSurfaceID>,
        now: Date = Date()
    ) throws {
        timer?.invalidate()
        timer = nil
        try repository.deleteExpired(atOrBefore: now)
        let restored = try repository.load()
        for schedule in restored
            where !validSurfaceIDs.contains(schedule.surfaceID) {
            try repository.delete(id: schedule.id)
        }
        schedules = restored.filter {
            validSurfaceIDs.contains($0.surfaceID)
        }
        rescheduleTimer()
    }

    func save(
        _ schedule: PaneInputSchedule,
        now: Date = Date()
    ) throws {
        guard schedule.fireAt > now else {
            throw PaneInputSchedulerError.pastDate
        }
        try repository.upsert(schedule)
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        sortSchedules()
        rescheduleTimer()
    }

    func delete(
        id: PaneInputScheduleID,
        now: Date = Date()
    ) throws {
        try repository.delete(id: id)
        schedules.removeAll { $0.id == id }
        rescheduleTimer()
    }

    func deleteAll(
        for surfaceID: TerminalSurfaceID,
        now: Date = Date()
    ) throws {
        try repository.deleteAll(for: surfaceID)
        schedules.removeAll { $0.surfaceID == surfaceID }
        rescheduleTimer()
    }

    func schedules(for surfaceID: TerminalSurfaceID) -> [PaneInputSchedule] {
        schedules.filter { $0.surfaceID == surfaceID }
    }

    func fireDue(now: Date = Date()) throws {
        let due = schedules.filter { $0.fireAt <= now }
        guard !due.isEmpty else {
            rescheduleTimer()
            return
        }

        for schedule in due {
            try repository.delete(id: schedule.id)
        }
        let dueIDs = Set(due.map(\.id))
        schedules.removeAll { dueIDs.contains($0.id) }
        rescheduleTimer()
        due.forEach(onFire)
    }

    @objc private func timerDidFire(_ timer: Timer) {
        do {
            try fireDue()
        } catch {
            onError(error)
        }
    }

    private func sortSchedules() {
        schedules.sort {
            if $0.fireAt != $1.fireAt {
                return $0.fireAt < $1.fireAt
            }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard timerEnabled, let next = schedules.first else { return }
        let timer = Timer(
            fireAt: next.fireAt,
            interval: 0,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
