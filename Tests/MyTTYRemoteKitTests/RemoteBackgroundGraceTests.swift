import Foundation
import Testing

@testable import MyTTYRemoteKit

@Suite("Remote background grace")
struct RemoteBackgroundGraceTests {
    @Test("keeps the session alive for thirty seconds")
    func graceDuration() {
        #expect(RemoteBackgroundGrace.graceDuration == 30)
    }

    @Test("begins protection when the app enters the background")
    func beginsProtection() {
        var grace = RemoteBackgroundGrace()
        #expect(!grace.isProtecting)

        #expect(grace.sceneDidEnterBackground() == .beginProtection)
        #expect(grace.isProtecting)
    }

    @Test("does not begin protection twice for repeated background events")
    func repeatedBackgroundEvents() {
        var grace = RemoteBackgroundGrace()

        #expect(grace.sceneDidEnterBackground() == .beginProtection)
        #expect(grace.sceneDidEnterBackground() == .none)
        #expect(grace.isProtecting)
    }

    @Test("ends protection when the app becomes active again")
    func endsProtectionOnActivate() {
        var grace = RemoteBackgroundGrace()
        _ = grace.sceneDidEnterBackground()

        #expect(grace.sceneDidActivate() == .endProtection)
        #expect(!grace.isProtecting)
    }

    @Test("activating without pending protection does nothing")
    func activateWithoutProtection() {
        var grace = RemoteBackgroundGrace()

        #expect(grace.sceneDidActivate() == .none)

        _ = grace.sceneDidEnterBackground()
        _ = grace.sceneDidActivate()
        #expect(grace.sceneDidActivate() == .none)
    }

    @Test("ends protection when the grace period expires")
    func endsProtectionOnExpiry() {
        var grace = RemoteBackgroundGrace()
        _ = grace.sceneDidEnterBackground()

        #expect(grace.deadlineExpired() == .endProtection)
        #expect(!grace.isProtecting)
    }

    @Test("a stale expiry after reactivation does nothing")
    func staleExpiry() {
        var grace = RemoteBackgroundGrace()
        _ = grace.sceneDidEnterBackground()
        _ = grace.sceneDidActivate()

        #expect(grace.deadlineExpired() == .none)
        #expect(!grace.isProtecting)
    }

    @Test("protection can restart after an earlier round ended")
    func restartsAfterEnd() {
        var grace = RemoteBackgroundGrace()
        _ = grace.sceneDidEnterBackground()
        _ = grace.deadlineExpired()

        #expect(grace.sceneDidEnterBackground() == .beginProtection)
        #expect(grace.isProtecting)
    }
}
