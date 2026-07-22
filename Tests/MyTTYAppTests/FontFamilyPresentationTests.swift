import AppKit
import Testing

@testable import MyTTYApp

@Suite("Font family presentation")
struct FontFamilyPresentationTests {
    @Test("uses the localized OpenType family name for the app language")
    func localizedFamilyName() {
        let nameTable = makeNameTable([
            NameRecord(
                languageID: 0x0409,
                nameID: 16,
                value: "Hiragino Sans"
            ),
            NameRecord(
                languageID: 0x0411,
                nameID: 16,
                value: "ヒラギノ角ゴシック"
            ),
        ])

        #expect(
            FontFamilyPresentation.displayName(
                for: "Hiragino Sans",
                language: .english,
                nameTableData: nameTable
            ) == "Hiragino Sans"
        )
        #expect(
            FontFamilyPresentation.displayName(
                for: "Hiragino Sans",
                language: .japanese,
                nameTableData: nameTable
            ) == "ヒラギノ角ゴシック"
        )
    }

    @Test("keeps the canonical family name without a requested translation")
    func missingLocalizedFamilyName() {
        let nameTable = makeNameTable([
            NameRecord(
                languageID: 0x0409,
                nameID: 16,
                value: "Example Sans"
            ),
        ])

        #expect(
            FontFamilyPresentation.displayName(
                for: "Example Sans",
                language: .japanese,
                nameTableData: nameTable
            ) == "Example Sans"
        )
    }

    @Test("renders a font family name using that family")
    func requestedFamily() {
        let font = FontFamilyPresentation.font(
            for: "Menlo",
            size: 13
        )

        #expect(font.familyName == "Menlo")
        #expect(font.pointSize == 13)
    }

    @Test("falls back to the system font for an unavailable family")
    func unavailableFamily() {
        let font = FontFamilyPresentation.font(
            for: "Definitely Not A Font",
            size: 13
        )

        #expect(font == NSFont.systemFont(ofSize: 13))
    }

    @Test("keeps the available families when nothing is selected")
    func menuFamiliesWithoutSelection() {
        #expect(
            FontFamilyPresentation.menuFamilies(
                available: ["Menlo", "Monaco"],
                selected: ""
            ) == ["Menlo", "Monaco"]
        )
    }

    @Test("keeps the available families when the selection is listed")
    func menuFamiliesWithListedSelection() {
        #expect(
            FontFamilyPresentation.menuFamilies(
                available: ["Menlo", "Monaco"],
                selected: "Monaco"
            ) == ["Menlo", "Monaco"]
        )
    }

    @Test("matches a listed selection case-insensitively")
    func menuFamiliesWithCaseInsensitiveSelection() {
        #expect(
            FontFamilyPresentation.menuFamilies(
                available: ["Menlo", "Monaco"],
                selected: "menlo"
            ) == ["Menlo", "Monaco"]
        )
    }

    @Test("inserts an unlisted selection in sort order")
    func menuFamiliesWithUnlistedSelection() {
        // Right after a cold boot fontd may not have indexed user fonts
        // yet; the configured family must still appear in the menu so
        // the selection never renders as empty.
        #expect(
            FontFamilyPresentation.menuFamilies(
                available: ["Arial", "Menlo"],
                selected: "JetBrains Mono"
            ) == ["Arial", "JetBrains Mono", "Menlo"]
        )
        #expect(
            FontFamilyPresentation.menuFamilies(
                available: ["Arial", "Menlo"],
                selected: "Zapfino Custom"
            ) == ["Arial", "Menlo", "Zapfino Custom"]
        )
    }

    @Test("lists only the selection when no families are available")
    func menuFamiliesWithEmptyAvailableList() {
        #expect(
            FontFamilyPresentation.menuFamilies(
                available: [],
                selected: "JetBrains Mono"
            ) == ["JetBrains Mono"]
        )
    }
}

private struct NameRecord {
    let languageID: UInt16
    let nameID: UInt16
    let value: String
}

private func makeNameTable(_ records: [NameRecord]) -> Data {
    var header = Data()
    var recordData = Data()
    var strings = Data()
    header.appendBigEndian(0)
    header.appendBigEndian(UInt16(records.count))
    header.appendBigEndian(UInt16(6 + records.count * 12))

    for record in records {
        let value = record.value.data(using: .utf16BigEndian) ?? Data()
        recordData.appendBigEndian(3)
        recordData.appendBigEndian(1)
        recordData.appendBigEndian(record.languageID)
        recordData.appendBigEndian(record.nameID)
        recordData.appendBigEndian(UInt16(value.count))
        recordData.appendBigEndian(UInt16(strings.count))
        strings.append(value)
    }
    return header + recordData + strings
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) {
            append(contentsOf: $0)
        }
    }
}
