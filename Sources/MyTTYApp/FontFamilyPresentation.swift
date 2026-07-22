import AppKit
import CoreText

enum FontFamilyPresentation {
    private static let displayNameCache = FontDisplayNameCache()

    static func font(for family: String, size: CGFloat) -> NSFont {
        guard !family.isEmpty else {
            return .systemFont(ofSize: size)
        }

        return NSFontManager.shared.font(
            withFamily: family,
            traits: [],
            weight: 5,
            size: size
        ) ?? NSFont(name: family, size: size)
            ?? .systemFont(ofSize: size)
    }

    /// The family list for the Settings picker. Right after a cold boot
    /// fontd may not have indexed user fonts yet, so the configured
    /// family can be missing from `availableFontFamilies`; keep it in
    /// the menu anyway so the current selection never renders as empty.
    static func menuFamilies(
        available: [String],
        selected: String
    ) -> [String] {
        guard !selected.isEmpty,
              !available.contains(where: {
                  $0.caseInsensitiveCompare(selected) == .orderedSame
              })
        else { return available }

        let index = available.firstIndex {
            $0.localizedCaseInsensitiveCompare(selected)
                == .orderedDescending
        } ?? available.endIndex
        var families = available
        families.insert(selected, at: index)
        return families
    }

    static func displayName(
        for family: String,
        language: ResolvedAppLanguage
    ) -> String {
        let key = "\(language)-\(family)"
        if let cached = displayNameCache.value(for: key) {
            return cached
        }

        let resolved = displayName(
            for: family,
            language: language,
            nameTableData: nameTableData(for: family)
        )
        displayNameCache.insert(resolved, for: key)
        return resolved
    }

    static func displayName(
        for family: String,
        language: ResolvedAppLanguage,
        nameTableData: Data?
    ) -> String {
        guard let nameTableData else { return family }
        return OpenTypeNameTable(data: nameTableData)
            .familyName(for: language) ?? family
    }

    private static func nameTableData(for family: String) -> Data? {
        let font = font(for: family, size: 13)
        guard let table = CTFontCopyTable(
            font,
            CTFontTableTag(kCTFontTableName),
            []
        ) else { return nil }
        return table as Data
    }
}

private final class FontDisplayNameCache: @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    func value(for key: String) -> String? {
        lock.withLock { values[key] }
    }

    func insert(_ value: String, for key: String) {
        lock.withLock { values[key] = value }
    }
}

private struct OpenTypeNameTable {
    private struct Record {
        let platformID: UInt16
        let encodingID: UInt16
        let languageID: UInt16
        let nameID: UInt16
        let length: Int
        let offset: Int
    }

    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func familyName(for language: ResolvedAppLanguage) -> String? {
        guard data.count >= 6,
              let count = uint16(at: 2).map(Int.init),
              let stringOffset = uint16(at: 4).map(Int.init),
              count <= (data.count - 6) / 12
        else { return nil }

        let languageTags = readLanguageTags(
            count: count,
            stringOffset: stringOffset
        )
        var candidates: [(score: Int, name: String)] = []
        for index in 0..<count {
            guard let record = record(at: 6 + index * 12),
                  record.nameID == 1 || record.nameID == 16,
                  matches(
                      record: record,
                      language: language,
                      languageTags: languageTags
                  ),
                  let name = decode(record: record, stringOffset: stringOffset),
                  !name.isEmpty
            else { continue }
            candidates.append((score(record), name))
        }
        return candidates.max { $0.score < $1.score }?.name
    }

    private func record(at offset: Int) -> Record? {
        guard let platformID = uint16(at: offset),
              let encodingID = uint16(at: offset + 2),
              let languageID = uint16(at: offset + 4),
              let nameID = uint16(at: offset + 6),
              let length = uint16(at: offset + 8),
              let stringOffset = uint16(at: offset + 10)
        else { return nil }
        return Record(
            platformID: platformID,
            encodingID: encodingID,
            languageID: languageID,
            nameID: nameID,
            length: Int(length),
            offset: Int(stringOffset)
        )
    }

    private func readLanguageTags(
        count: Int,
        stringOffset: Int
    ) -> [String] {
        guard uint16(at: 0) == 1 else { return [] }
        let countOffset = 6 + count * 12
        guard let tagCount = uint16(at: countOffset).map(Int.init) else {
            return []
        }

        return (0..<tagCount).compactMap { index in
            let offset = countOffset + 2 + index * 4
            guard let length = uint16(at: offset).map(Int.init),
                  let relativeOffset = uint16(at: offset + 2).map(Int.init),
                  let value = bytes(
                      at: stringOffset + relativeOffset,
                      length: length
                  )
            else { return nil }
            return String(data: value, encoding: .utf16BigEndian)
        }
    }

    private func matches(
        record: Record,
        language: ResolvedAppLanguage,
        languageTags: [String]
    ) -> Bool {
        switch record.platformID {
        case 0:
            guard record.languageID >= 0x8000 else { return false }
            let index = Int(record.languageID - 0x8000)
            guard languageTags.indices.contains(index) else { return false }
            return languageTags[index].lowercased().hasPrefix(
                language == .japanese ? "ja" : "en"
            )
        case 1:
            return record.languageID == (language == .japanese ? 11 : 0)
        case 3:
            let primaryLanguageID = record.languageID & 0x03FF
            return primaryLanguageID == (language == .japanese ? 0x11 : 0x09)
        default:
            return false
        }
    }

    private func decode(record: Record, stringOffset: Int) -> String? {
        guard let value = bytes(
            at: stringOffset + record.offset,
            length: record.length
        ) else { return nil }

        let encoding: String.Encoding
        switch record.platformID {
        case 0, 3:
            encoding = .utf16BigEndian
        case 1 where record.encodingID == 1:
            encoding = .shiftJIS
        case 1:
            encoding = .macOSRoman
        default:
            return nil
        }
        return String(data: value, encoding: encoding)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func score(_ record: Record) -> Int {
        let nameScore = record.nameID == 16 ? 100 : 0
        let platformScore: Int = switch record.platformID {
        case 3: 30
        case 0: 20
        case 1: 10
        default: 0
        }
        return nameScore + platformScore
    }

    private func uint16(at offset: Int) -> UInt16? {
        guard let value = bytes(at: offset, length: 2) else { return nil }
        return value.reduce(0) { ($0 << 8) | UInt16($1) }
    }

    private func bytes(at offset: Int, length: Int) -> Data? {
        guard offset >= 0,
              length >= 0,
              offset <= data.count,
              length <= data.count - offset
        else { return nil }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: length)
        return data[start..<end]
    }
}
