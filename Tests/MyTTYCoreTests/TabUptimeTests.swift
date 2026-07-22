import Foundation
import Testing

@testable import MyTTYCore

@Suite("Tab uptime")
struct TabUptimeTests {
    @Test("shows seconds alone under a minute")
    func secondsOnly() {
        #expect(TabUptimeFormatter.string(from: 53) == "53s")
        #expect(TabUptimeFormatter.string(from: 0) == "0s")
        #expect(TabUptimeFormatter.string(from: 59) == "59s")
    }

    @Test("keeps zero components below the leading unit")
    func zeroPadding() {
        #expect(TabUptimeFormatter.string(from: 60) == "1m 0s")
        #expect(TabUptimeFormatter.string(from: 3600) == "1h 0m 0s")
        #expect(
            TabUptimeFormatter.string(from: 2 * 3600 + 53) == "2h 0m 53s"
        )
    }

    @Test("shows at most three components from the leading unit")
    func componentLimit() {
        #expect(
            TabUptimeFormatter.string(from: 4 * 86400 + 60 + 51)
                == "4d 0h 1m"
        )
        #expect(
            TabUptimeFormatter.string(
                from: 36 * 86400 + 2 * 3600 + 10 * 60 + 1
            ) == "5w 1d 2h"
        )
        #expect(TabUptimeFormatter.string(from: 604800) == "1w 0d 0h")
    }

    @Test("clamps negative and non-finite intervals to zero")
    func invalidIntervals() {
        #expect(TabUptimeFormatter.string(from: -5) == "0s")
        #expect(TabUptimeFormatter.string(from: .nan) == "0s")
        #expect(TabUptimeFormatter.string(from: .infinity) == "0s")
    }

    @Test("truncates fractional seconds")
    func fractionalSeconds() {
        #expect(TabUptimeFormatter.string(from: 53.9) == "53s")
    }
}
