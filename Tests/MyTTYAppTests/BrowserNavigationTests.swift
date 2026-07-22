import AppKit
import Foundation
import Testing

@testable import MyTTYApp

@Suite("Browser navigation")
struct BrowserNavigationTests {
    @Test("resolves web addresses and local HTML paths")
    func resolvesAddresses() throws {
        let base = URL(fileURLWithPath: "/Users/example/project", isDirectory: true)

        #expect(
            BrowserAddress.resolve("https://example.com/docs", relativeTo: base)
                == URL(string: "https://example.com/docs")
        )
        #expect(
            BrowserAddress.resolve("preview/index.html", relativeTo: base)
                == base.appendingPathComponent("preview/index.html")
        )
    }

    @Test("grants local HTML access to its containing directory")
    func localHTMLLoadPlan() {
        let file = URL(fileURLWithPath: "/tmp/site/index.html")

        #expect(
            BrowserLoadPlan(url: file)
                == .file(
                    file,
                    readAccess: URL(fileURLWithPath: "/tmp/site", isDirectory: true)
                )
        )
        let web = URL(string: "https://example.com")!
        #expect(BrowserLoadPlan(url: web) == .request(URLRequest(url: web)))
    }

    @Test("offers every command-click link destination in order")
    func linkDestinations() {
        #expect(
            LinkOpenDestination.allCases == [
                .externalBrowser,
                .newTab,
                .newPaneRight,
                .newPaneDown,
                .copyLink,
            ]
        )
    }

    @Test("copies a link without changing its URL text")
    @MainActor
    func copyLink() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("mytty-link-test-\(UUID().uuidString)")
        )
        defer { pasteboard.clearContents() }
        let url = try #require(
            URL(string: "https://example.com/docs?q=mytty%20terminal#links")
        )

        LinkClipboard.copy(url, to: pasteboard)

        #expect(
            pasteboard.string(forType: .string)
                == "https://example.com/docs?q=mytty%20terminal#links"
        )
    }

    @Test("browser toolbar offers a close button")
    @MainActor
    func closeButton() throws {
        let browser = BrowserPaneView(url: URL(string: "about:blank")!)
        var closeRequested = false
        browser.onClose = { closeRequested = true }

        let closeButton = try #require(
            browser.descendantButtons.first {
                $0.accessibilityLabel() == "Close Browser"
            }
        )
        closeButton.performClick(nil)

        #expect(closeRequested)
    }

    @Test("opens and closes find within the browser pane")
    @MainActor
    func findPresentation() {
        let browser = BrowserPaneView(url: URL(string: "about:blank")!)

        #expect(!browser.isFindPresented)

        browser.showFind()

        #expect(browser.isFindPresented)

        browser.closeFind()

        #expect(!browser.isFindPresented)
    }

    @Test("recognizes a responder inside the browser pane")
    @MainActor
    func findResponderScope() {
        let browser = BrowserPaneView(url: URL(string: "about:blank")!)
        let webContent = NSView()
        let unrelated = NSView()
        browser.addSubview(webContent)

        #expect(browser.containsFirstResponder(webContent))
        #expect(!browser.containsFirstResponder(unrelated))
        #expect(!browser.containsFirstResponder(nil))
    }

    @Test("treats a scheme-less absolute path as a local HTML file")
    func schemelessAbsolutePathLoadPlan() {
        let schemeless = URL(string: "/tmp/site/index.html")!

        #expect(
            BrowserLoadPlan(url: schemeless)
                == .file(
                    URL(fileURLWithPath: "/tmp/site/index.html"),
                    readAccess: URL(fileURLWithPath: "/tmp/site", isDirectory: true)
                )
        )
    }

    @Test("normalizes a scheme-less tilde path to a file URL under the home directory")
    func normalizesTildePath() {
        let normalized = BrowserAddress.normalize(
            URL(string: "~/site/index.html")!
        )

        let expected = URL(
            fileURLWithPath: (NSHomeDirectory() as NSString)
                .appendingPathComponent("site/index.html")
        )
        #expect(normalized == expected)
    }

    @Test("normalizes a percent-encoded scheme-less path")
    func normalizesPercentEncodedPath() {
        let normalized = BrowserAddress.normalize(
            URL(string: "/tmp/report%20v2/index.html")!
        )

        #expect(normalized.isFileURL)
        #expect(normalized.path.contains("report v2"))
    }

    @Test("leaves URLs with a scheme unchanged")
    func normalizePassesThroughSchemedURL() {
        let url = URL(string: "https://example.com/docs")!

        #expect(BrowserAddress.normalize(url) == url)
    }

    @Test("resolves a scheme-less relative link with a trailing encoded space against the pane's working directory")
    func resolveLinkRelativeWithTrailingSpace() {
        let base = URL(fileURLWithPath: "/Users/example/project", isDirectory: true)
        let link = URL(string: "./llmeter-report/index.html%20")!

        let resolved = BrowserAddress.resolveLink(link, workingDirectory: base)

        #expect(
            resolved.standardizedFileURL
                == URL(fileURLWithPath: "/Users/example/project/llmeter-report/index.html")
                    .standardizedFileURL
        )
        #expect(resolved.isFileURL)
        #expect(!resolved.path.hasSuffix(" "))
        #expect(!resolved.absoluteString.contains("%20"))
    }

    @Test("leaves a scheme-less relative link unresolved when there is no working directory")
    func resolveLinkRelativeWithoutWorkingDirectory() {
        let link = URL(string: "./llmeter-report/index.html%20")!

        let resolved = BrowserAddress.resolveLink(link, workingDirectory: nil)

        #expect(resolved == link)
    }

    @Test("resolves a scheme-less absolute link regardless of the working directory")
    func resolveLinkAbsolutePath() {
        let base = URL(fileURLWithPath: "/Users/example/project", isDirectory: true)
        let link = URL(string: "/tmp/site/index.html%20")!

        let resolved = BrowserAddress.resolveLink(link, workingDirectory: base)

        #expect(resolved.isFileURL)
        #expect(resolved.path == "/tmp/site/index.html")
    }

    @Test("resolves a scheme-less tilde link under the home directory")
    func resolveLinkTildePath() {
        let base = URL(fileURLWithPath: "/Users/example/project", isDirectory: true)
        let link = URL(string: "~/site/index.html")!

        let resolved = BrowserAddress.resolveLink(link, workingDirectory: base)

        let expected = URL(
            fileURLWithPath: (NSHomeDirectory() as NSString)
                .appendingPathComponent("site/index.html")
        )
        #expect(resolved == expected)
    }

    @Test("leaves a schemed link unchanged even with a working directory")
    func resolveLinkPassesThroughSchemedURL() {
        let base = URL(fileURLWithPath: "/Users/example/project", isDirectory: true)
        let url = URL(string: "https://example.com/docs")!

        #expect(BrowserAddress.resolveLink(url, workingDirectory: base) == url)
    }

    @Test("claims the Safari that ships with the running macOS")
    func safariApplicationNameForUserAgent() {
        #expect(
            BrowserPaneView.applicationNameForUserAgent(macOSMajorVersion: 26)
                == "Version/26.0 Safari/605.1.15"
        )
        #expect(
            BrowserPaneView.applicationNameForUserAgent(macOSMajorVersion: 27)
                == "Version/27.0 Safari/605.1.15"
        )
        #expect(
            BrowserPaneView.applicationNameForUserAgent(macOSMajorVersion: 15)
                == "Version/18.0 Safari/605.1.15"
        )
    }
}

private extension NSView {
    var descendantButtons: [NSButton] {
        subviews.flatMap { view in
            (view as? NSButton).map { [$0] } ?? view.descendantButtons
        }
    }
}
