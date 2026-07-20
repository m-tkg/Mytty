import Foundation
import Testing

@testable import MyTTYApp

@Suite("Ghostty theme gallery")
struct GhosttyThemeGalleryTests {
    @Test("retains an unlisted selection and filters thumbnails by name")
    func optionsAndFiltering() {
        let catalog = [
            preview("3024 Night", background: "111111"),
            preview("Paper Light", background: "fafafa"),
        ]

        let options = GhosttyThemeGalleryModel.options(
            currentTheme: "Private Theme",
            catalog: catalog
        )

        #expect(options.map(\.name) == [
            "Private Theme",
            "3024 Night",
            "Paper Light",
        ])
        #expect(GhosttyThemeGalleryModel.filtered(
            options,
            query: "night"
        ).map(\.name) == ["3024 Night"])
        #expect(GhosttyThemeGalleryModel.filtered(
            options,
            query: "  "
        ) == options)
    }

    private func preview(
        _ name: String,
        background: String
    ) -> GhosttyThemePreview {
        GhosttyThemePreview(
            name: name,
            data: Data(
                "background = #\(background)\nforeground = #eeeeee".utf8
            )
        )
    }
}
