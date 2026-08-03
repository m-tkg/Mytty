import Testing

@testable import MyTTYCore

@Suite("Bookmark validation")
struct BookmarkValidationTests {
    @Test("keeps a bookmark whose line hasn't moved or changed")
    func normalKeep() {
        #expect(
            BookmarkValidation.shouldRemove(
                createdRow: 12,
                currentRow: 12,
                currentX: 0,
                screenIsActive: true,
                textMatches: true
            ) == false
        )
    }

    @Test("removes a bookmark relocated to the top-left by eviction")
    func evictedRemove() {
        #expect(
            BookmarkValidation.shouldRemove(
                createdRow: 12,
                currentRow: 0,
                currentX: 0,
                screenIsActive: true,
                textMatches: true
            ) == true
        )
    }

    @Test("keeps a bookmark while the alternate screen is active, even if it reads as evicted or mismatched")
    func altScreenSkip() {
        #expect(
            BookmarkValidation.shouldRemove(
                createdRow: 12,
                currentRow: 0,
                currentX: 0,
                screenIsActive: false,
                textMatches: false
            ) == false
        )
    }

    @Test("removes a bookmark whose line no longer matches its snapshot")
    func textMismatchRemove() {
        #expect(
            BookmarkValidation.shouldRemove(
                createdRow: 12,
                currentRow: 12,
                currentX: 0,
                screenIsActive: true,
                textMatches: false
            ) == true
        )
    }

    @Test("keeps a bookmark legitimately created at row 0 while its text still matches")
    func createdAtRowZeroEdge() {
        #expect(
            BookmarkValidation.shouldRemove(
                createdRow: 0,
                currentRow: 0,
                currentX: 0,
                screenIsActive: true,
                textMatches: true
            ) == false
        )
    }

    @Test("still removes a row-0 bookmark whose text has since changed")
    func createdAtRowZeroTextMismatch() {
        #expect(
            BookmarkValidation.shouldRemove(
                createdRow: 0,
                currentRow: 0,
                currentX: 0,
                screenIsActive: true,
                textMatches: false
            ) == true
        )
    }

    @Test("a nonzero column at row 0 is not treated as eviction by itself")
    func rowZeroNonzeroColumnIsNotEviction() {
        #expect(
            BookmarkValidation.shouldRemove(
                createdRow: 12,
                currentRow: 0,
                currentX: 3,
                screenIsActive: true,
                textMatches: true
            ) == false
        )
    }
}
