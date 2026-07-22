import AppKit
import Foundation

enum BrowserAddress {
    static func resolve(_ value: String, relativeTo base: URL) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let url = URL(string: value), url.scheme != nil {
            return url
        }

        let expanded = (value as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return base.appendingPathComponent(expanded)
    }

    static func normalize(_ url: URL) -> URL {
        guard url.scheme == nil else { return url }

        let original = url.absoluteString
        let decoded = original.removingPercentEncoding ?? original
        let expanded = (decoded as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return url
    }
}

enum BrowserLoadPlan: Equatable {
    case file(URL, readAccess: URL)
    case request(URLRequest)

    init(url: URL) {
        let url = BrowserAddress.normalize(url)
        if url.isFileURL {
            self = .file(
                url,
                readAccess: url.deletingLastPathComponent()
            )
        } else {
            self = .request(URLRequest(url: url))
        }
    }
}

enum LinkOpenDestination: CaseIterable, Equatable {
    case externalBrowser
    case newTab
    case newPaneRight
    case newPaneDown
    case copyLink
}

@MainActor
enum LinkClipboard {
    static func copy(
        _ url: URL,
        to pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }
}
