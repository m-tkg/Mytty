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

    /// Resolves a link clicked in the terminal: scheme-less paths become
    /// file URLs, resolving relative paths against the pane's working
    /// directory. URLs that already have a scheme pass through untouched.
    static func resolveLink(_ url: URL, workingDirectory: URL?) -> URL {
        guard url.scheme == nil else { return url }

        let raw = url.absoluteString
        let decoded = raw.removingPercentEncoding ?? raw
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return url }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        guard let base = workingDirectory else { return url }
        return URL(fileURLWithPath: trimmed, relativeTo: base).standardizedFileURL
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
