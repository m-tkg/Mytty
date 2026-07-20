import Testing

@testable import GhosttyAdapter

@Suite("Ghostty library")
struct GhosttyLibraryTests {
    @Test("exposes build metadata from the pinned native library")
    func buildMetadata() {
        let info = GhosttyLibrary.buildInfo()

        #expect(!info.version.isEmpty)
        #expect(info.buildMode == .releaseFast)
    }
}

