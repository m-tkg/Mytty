import Foundation

/// Where Attention pushes are relayed. The Mac and the iOS app both read
/// this one constant — the phone registers with it and the Mac posts to
/// it — so there is no way for the two ends to be pointed at different
/// relays. Self-hosting is a matter of deploying
/// `cloudflare/push-relay` and editing this line.
public enum PushRelay {
    public static let defaultURL = URL(
        string: "https://mytty-push-relay.m-tkg.workers.dev"
    )!

    public static func registerURL(base: URL = defaultURL) -> URL {
        base.appendingPathComponent("v1").appendingPathComponent("register")
    }

    public static func pushURL(base: URL = defaultURL) -> URL {
        base.appendingPathComponent("v1").appendingPathComponent("push")
    }

    /// What a phone shows when it cannot decrypt the sealed alert — an
    /// older build without the notification service extension, or a Mac
    /// it has since unpaired. Deliberately says nothing specific.
    public static let placeholderTitle = "Mytty"
}
