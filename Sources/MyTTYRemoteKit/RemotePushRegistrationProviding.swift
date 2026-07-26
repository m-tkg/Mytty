import Combine
import Foundation

/// What a client hands the Mac so it can address Attention pushes at this
/// device through the relay. The device token itself never appears here:
/// the client registers it with the relay directly and passes on only the
/// resulting handle.
public struct RemotePushRelayRegistration: Equatable, Sendable {
    public var pushID: String
    public var relaySecret: String

    public init(pushID: String, relaySecret: String) {
        self.pushID = pushID
        self.relaySecret = relaySecret
    }
}

/// Supplies `RemoteClient` with the current push relay registration, if the
/// platform has one. Only the iOS remote does — a Mac acting as a client
/// has no APNs registration to hand over and passes nil, which leaves
/// `RemoteClient` sending nothing.
@MainActor
public protocol RemotePushRegistrationProviding: AnyObject {
    var currentPushRelayRegistration: RemotePushRelayRegistration? { get }
    /// Fires whenever `currentPushRelayRegistration` changes. The token can
    /// land after a session is already up (the first launch asks for
    /// permission), so `RemoteClient` re-sends on every change.
    var pushRelayRegistrationChanged: AnyPublisher<Void, Never> { get }
}
