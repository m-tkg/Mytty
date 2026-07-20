import Foundation
import MyTTYCore

@MainActor
final class AgentEventServer {
    static let socketEnvironmentKey = AgentHookBridge.socketEnvironmentKey
    static let surfaceEnvironmentKey = AgentHookBridge.surfaceEnvironmentKey
    static let capabilityEnvironmentKey = AgentHookBridge.capabilityEnvironmentKey
    static let controlSocketEnvironmentKey =
        AgentHookBridge.controlSocketEnvironmentKey
    static let controlExecutableEnvironmentKey =
        AgentHookBridge.controlExecutableEnvironmentKey

    private let socketURL: URL
    private let aiControlSocketURL: URL
    private let aiControlExecutableURL: URL
    private let onEvent: (AgentEvent) throws -> Bool
    private let onError: (Error) -> Void

    private var transport: UnixSocketTransport?
    private var authorizer = AgentEventAuthorizer()

    init(
        socketURL: URL,
        aiControlSocketURL: URL,
        aiControlExecutableURL: URL,
        onEvent: @escaping (AgentEvent) throws -> Bool,
        onError: @escaping (Error) -> Void
    ) {
        self.socketURL = socketURL
        self.aiControlSocketURL = aiControlSocketURL
        self.aiControlExecutableURL = aiControlExecutableURL
        self.onEvent = onEvent
        self.onError = onError
    }

    func start() throws {
        stop()
        let transport = UnixSocketTransport(
            socketURL: socketURL,
            label: "dev.mytty.agent-events",
            onRequest: { [weak self] request, reply in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    reply(self.responseData(for: request))
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.onError(error)
                }
            }
        )
        try transport.start()
        self.transport = transport
    }

    func stop() {
        transport?.stop()
        transport = nil
    }

    func environment(
        for surfaceID: TerminalSurfaceID
    ) throws -> [String: String] {
        let capability = UUID().uuidString.replacingOccurrences(
            of: "-",
            with: ""
        ) + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try authorizer.register(capability: capability, for: surfaceID)
        return [
            Self.socketEnvironmentKey: socketURL.path,
            Self.surfaceEnvironmentKey: surfaceID.rawValue.uuidString,
            Self.capabilityEnvironmentKey: capability,
            Self.controlSocketEnvironmentKey: aiControlSocketURL.path,
            Self.controlExecutableEnvironmentKey: aiControlExecutableURL.path,
        ]
    }

    func revoke(surface surfaceID: TerminalSurfaceID) {
        authorizer.revoke(surface: surfaceID)
    }

    private func responseData(for request: Data?) -> Data {
        let response: AgentEventServerResponse
        guard let request else {
            response = .failure(code: "request-too-large")
            return encode(response)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(
                AgentEventEnvelope.self,
                from: request
            )
            let event = try authorizer.authorize(envelope)
            response = .success(inserted: try onEvent(event))
        } catch is AgentEventAuthorizationError {
            response = .failure(code: "unauthorized")
        } catch is DecodingError {
            response = .failure(code: "invalid-request")
        } catch {
            onError(error)
            response = .failure(code: "internal-error")
        }
        return encode(response)
    }

    private func encode(_ response: AgentEventServerResponse) -> Data {
        var data = (try? JSONEncoder().encode(response)) ?? Data()
        data.append(0x0A)
        return data
    }
}
