import Foundation

/// Cyclic index arithmetic shared by Next/Previous Tab and Next/Previous
/// Window: stepping past either end wraps around instead of clamping.
public enum CyclicSelection {
    /// The index `offset` positions away from `current` within `count`
    /// items, wrapping at both ends. `nil` when there is nothing to select
    /// (`count <= 0`).
    public static func index(current: Int, offset: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let wrapped = (current + offset) % count
        return wrapped < 0 ? wrapped + count : wrapped
    }
}
