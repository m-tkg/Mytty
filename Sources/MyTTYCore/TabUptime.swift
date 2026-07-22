import Foundation

/// Formats how long a tab has been open, e.g. "2h 0m 53s".
///
/// Units are weeks, days, hours, minutes, and seconds. Components above
/// the leading nonzero unit are dropped, and at most three components are
/// shown starting from that unit — so zero components inside the window
/// stay visible ("4d 0h 1m") while anything below it is cut off.
public enum TabUptimeFormatter {
    private static let units: [(suffix: String, seconds: Int)] = [
        ("w", 7 * 24 * 60 * 60),
        ("d", 24 * 60 * 60),
        ("h", 60 * 60),
        ("m", 60),
        ("s", 1),
    ]
    private static let maxComponents = 3

    public static func string(from interval: TimeInterval) -> String {
        var remaining = Int(interval.isFinite ? min(max(0, interval), 1e15) : 0)
        let values = units.map { unit in
            let value = remaining / unit.seconds
            remaining %= unit.seconds
            return value
        }

        let leading = values.firstIndex(where: { $0 > 0 })
            ?? units.index(before: units.endIndex)
        return Array(zip(values, units))[leading...]
            .prefix(maxComponents)
            .map { value, unit in "\(value)\(unit.suffix)" }
            .joined(separator: " ")
    }
}
