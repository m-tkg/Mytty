import Testing

@testable import MyTTYCore

@Suite("Cyclic selection")
struct CyclicSelectionTests {
    @Test("steps forward and backward without wrapping")
    func withinBounds() {
        #expect(CyclicSelection.index(current: 1, offset: 1, count: 5) == 2)
        #expect(CyclicSelection.index(current: 3, offset: -1, count: 5) == 2)
        #expect(CyclicSelection.index(current: 2, offset: 0, count: 5) == 2)
    }

    @Test("wraps around at either end")
    func wrapping() {
        #expect(CyclicSelection.index(current: 4, offset: 1, count: 5) == 0)
        #expect(CyclicSelection.index(current: 0, offset: -1, count: 5) == 4)
        #expect(CyclicSelection.index(current: 4, offset: 6, count: 5) == 0)
    }

    @Test("handles negative offsets larger than count")
    func negativeOffset() {
        #expect(CyclicSelection.index(current: 0, offset: -6, count: 5) == 4)
        #expect(CyclicSelection.index(current: 2, offset: -11, count: 5) == 1)
    }

    @Test("has nothing to select with zero items, and only one with a single item")
    func edgeCounts() {
        #expect(CyclicSelection.index(current: 0, offset: 1, count: 0) == nil)
        #expect(CyclicSelection.index(current: 0, offset: 5, count: 1) == 0)
        #expect(CyclicSelection.index(current: 0, offset: -5, count: 1) == 0)
    }
}
