import AppKit
import Foundation
import Testing

@testable import MyTTYApp

@Suite("Application icon")
struct ApplicationIconTests {
    @Test("loads the bundled PNG as a non-template app icon")
    func bundledIcon() throws {
        let icon = try #require(ApplicationIcon.image)

        #expect(icon.size.width > 0)
        #expect(icon.size.height > 0)
        #expect(!icon.isTemplate)
        let representation = try #require(icon.representations.first)
        #expect(representation.pixelsWide == 1_024)
        #expect(representation.pixelsHigh == 1_024)
    }

    @Test("finds a resource in the flat release bundle layout")
    func flatReleaseBundle() throws {
        let fixture = try ResourceBundleFixture(layout: .flat)
        defer { fixture.remove() }

        let result = ApplicationResources.resourceURL(
            named: "AppIcon",
            withExtension: "png",
            searchRoots: [fixture.resourcesDirectory]
        )

        #expect(result == fixture.resource)
    }

    @Test("finds a resource in the structured SwiftPM bundle layout")
    func structuredSwiftPMBundle() throws {
        let fixture = try ResourceBundleFixture(layout: .structured)
        defer { fixture.remove() }

        let result = ApplicationResources.resourceURL(
            named: "mark-github-16",
            withExtension: "svg",
            searchRoots: [fixture.resourcesDirectory]
        )

        #expect(result == fixture.resource)
    }

    @Test("searches above an XCTest bundle for legacy SwiftPM resources")
    func legacySwiftPMTestBundle() throws {
        let fixture = try ResourceBundleFixture(layout: .flat)
        defer { fixture.remove() }
        let executable = fixture.resourcesDirectory
            .appendingPathComponent(
                "MyTTYAppTests.xctest/Contents/MacOS/MyTTYAppTests"
            )

        let result = ApplicationResources.resourceURL(
            named: "AppIcon",
            withExtension: "png",
            searchRoots: ApplicationResources.executableSearchRoots(
                for: executable
            )
        )

        #expect(result == fixture.resource)
    }

    @Test("uses the XCTest bundle argument from legacy SwiftPM runners")
    func legacySwiftPMRunnerArguments() throws {
        let fixture = try ResourceBundleFixture(layout: .flat)
        defer { fixture.remove() }
        let testBundle = fixture.resourcesDirectory
            .appendingPathComponent("MyTTYAppTests.xctest", isDirectory: true)

        let result = ApplicationResources.resourceURL(
            named: "AppIcon",
            withExtension: "png",
            searchRoots: ApplicationResources.commandLineSearchRoots(
                arguments: ["/usr/bin/xctest", testBundle.path]
            )
        )

        #expect(result == fixture.resource)
    }

    @Test("searches beside an XCTest bundle for legacy SwiftPM resources")
    func legacySwiftPMTokenBundle() throws {
        let fixture = try ResourceBundleFixture(layout: .flat)
        defer { fixture.remove() }
        let testBundle = fixture.resourcesDirectory
            .appendingPathComponent("myttyPackageTests.xctest", isDirectory: true)

        let result = ApplicationResources.resourceURL(
            named: "AppIcon",
            withExtension: "png",
            searchRoots: ApplicationResources.bundleSearchRoots(
                bundleURL: testBundle,
                resourceURL: testBundle.appendingPathComponent(
                    "Contents/Resources",
                    isDirectory: true
                )
            )
        )

        #expect(result == fixture.resource)
    }
}

private struct ResourceBundleFixture {
    enum Layout {
        case flat
        case structured
    }

    let directory: URL
    let resourcesDirectory: URL
    let resource: URL

    init(layout: Layout) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        resourcesDirectory = directory
            .appendingPathComponent("Resources", isDirectory: true)
        let bundle = resourcesDirectory
            .appendingPathComponent("mytty_MyTTYApp.bundle", isDirectory: true)
        let resourceDirectory: URL
        let name: String
        switch layout {
        case .flat:
            resourceDirectory = bundle
            name = "AppIcon.png"
        case .structured:
            resourceDirectory = bundle
                .appendingPathComponent("Contents/Resources", isDirectory: true)
            name = "mark-github-16.svg"
        }
        try FileManager.default.createDirectory(
            at: resourceDirectory,
            withIntermediateDirectories: true
        )
        resource = resourceDirectory.appendingPathComponent(name)
        try Data("fixture".utf8).write(to: resource)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
