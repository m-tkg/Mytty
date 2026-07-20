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
