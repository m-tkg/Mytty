import Foundation
import Testing

@testable import MyTTYCore

@Suite("Uncaught exception log")
struct UncaughtExceptionLogTests {
    @Test("rendered() includes name, reason, version, and stack frames")
    func renderedIncludesFields() {
        let report = UncaughtExceptionReport(
            name: "NSInternalInconsistencyException",
            reason: "something went wrong",
            callStack: ["0 CoreFoundation 0x1 __exceptionPreprocess", "1 libobjc 0x2 objc_exception_throw"],
            timestamp: Date(timeIntervalSince1970: 0),
            applicationVersion: "1.2.3",
            source: "reportException"
        )

        let rendered = report.rendered()

        #expect(rendered.contains("NSInternalInconsistencyException"))
        #expect(rendered.contains("something went wrong"))
        #expect(rendered.contains("1.2.3"))
        #expect(rendered.contains("reportException"))
        #expect(rendered.contains("__exceptionPreprocess"))
        #expect(rendered.contains("objc_exception_throw"))
        #expect(rendered.contains("1970-01-01"))
    }

    @Test("rendered() handles a nil reason")
    func renderedHandlesNilReason() {
        let report = UncaughtExceptionReport(
            name: "SomeException",
            reason: nil,
            callStack: [],
            timestamp: Date(),
            applicationVersion: "1.0.0",
            source: "uncaughtHandler"
        )

        let rendered = report.rendered()

        #expect(rendered.contains("(no reason)"))
        #expect(rendered.contains("(no call stack)"))
    }

    @Test("rendered() strips control characters from name and reason")
    func renderedStripsControlCharacters() {
        let report = UncaughtExceptionReport(
            name: "Bad\u{0007}Name",
            reason: "Bad\u{0001}Reason\nkeeps newline\tand tab",
            callStack: [],
            timestamp: Date(),
            applicationVersion: "1.0.0",
            source: "uncaughtHandler"
        )

        let rendered = report.rendered()

        #expect(rendered.contains("BadName"))
        #expect(!rendered.contains("\u{0007}"))
        #expect(!rendered.contains("\u{0001}"))
        #expect(rendered.contains("BadReason\nkeeps newline\tand tab"))
    }

    @Test("rendered() clamps overly long name and reason")
    func renderedClampsLength() {
        let longName = String(repeating: "n", count: 10_000)
        let longReason = String(repeating: "r", count: 10_000)
        let report = UncaughtExceptionReport(
            name: longName,
            reason: longReason,
            callStack: [],
            timestamp: Date(),
            applicationVersion: "1.0.0",
            source: "uncaughtHandler"
        )

        let rendered = report.rendered()

        #expect(!rendered.contains(longName))
        #expect(!rendered.contains(longReason))
        // A clamped run of 4096 characters should still be present.
        #expect(rendered.contains(String(repeating: "n", count: 4096)))
        #expect(rendered.contains(String(repeating: "r", count: 4096)))
    }

    @Test("append() creates the file and parent directory")
    func appendCreatesFile() {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("uncaught-exceptions.log", isDirectory: false)
        let log = UncaughtExceptionLog(fileURL: fileURL)

        log.append(makeReport())

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let contents = try? String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents?.contains("TestException") == true)
    }

    @Test("append() grows the file on a second call")
    func appendGrowsFile() {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("uncaught-exceptions.log", isDirectory: false)
        let log = UncaughtExceptionLog(fileURL: fileURL)

        log.append(makeReport())
        let sizeAfterFirst = fileSize(at: fileURL)
        log.append(makeReport())
        let sizeAfterSecond = fileSize(at: fileURL)

        #expect(sizeAfterSecond > sizeAfterFirst)
    }

    @Test("append() resets the file once it exceeds the maximum size")
    func appendResetsWhenOversized() {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("uncaught-exceptions.log", isDirectory: false)
        // A cap that comfortably fits one report but not two, so the
        // second append grows past it and the third must reset.
        let singleReportSize = makeReport().rendered().utf8.count
        let log = UncaughtExceptionLog(
            fileURL: fileURL,
            maximumFileSize: singleReportSize + singleReportSize / 2
        )

        log.append(makeReport())
        let sizeAfterFirst = fileSize(at: fileURL)

        log.append(makeReport())
        let sizeAfterSecond = fileSize(at: fileURL)
        #expect(sizeAfterSecond > sizeAfterFirst)

        log.append(makeReport())
        let sizeAfterThird = fileSize(at: fileURL)

        #expect(sizeAfterThird < sizeAfterSecond)
        #expect(sizeAfterThird == sizeAfterFirst)
    }

    private func makeReport() -> UncaughtExceptionReport {
        UncaughtExceptionReport(
            name: "TestException",
            reason: "test reason",
            callStack: ["0 Test 0x1 frame"],
            timestamp: Date(),
            applicationVersion: "1.0.0",
            source: "uncaughtHandler"
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil ?? 0
    }
}
