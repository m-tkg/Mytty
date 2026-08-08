import AppKit
import Combine
import Foundation
import MyTTYCore
import MyTTYRemoteKit

/// Owns one `RemoteClient` per paired host and routes its output to every
/// remote pane mirroring that host.
///
/// Connections are shared rather than per-pane: two panes onto the same Mac
/// use one TCP session, which is also what the host's watch tracker expects
/// (it keys watches by pane, not by connection). A client is torn down as
/// soon as its last pane closes, so an app with no remote panes holds no
/// remote connections.
///
/// This is app-wide rather than per-window, because remote panes in
/// different windows can point at the same host and must not each open
/// their own session.
@MainActor
final class RemotePaneConnectionCoordinator {
    private let store: RemoteHostStore
    private let onError: (Error) -> Void

    private struct HostSession {
        let client: RemoteClient
        var observers: Set<AnyCancellable> = []
        var panes: [TerminalSurfaceID: RemotePaneRegistration] = [:]
    }

    private struct RemotePaneRegistration {
        /// The pane's ID on the host, which every protocol message is
        /// addressed by.
        let remotePaneID: String
        weak var view: RemotePaneView?
    }

    /// The host's agent status for each attached pane, refreshed on every
    /// snapshot. Held here rather than in `RemotePaneState` because it is
    /// live data: persisting it would restore a pane claiming an agent was
    /// running on a Mac this one has not even reconnected to yet.
    private(set) var agentStatusByPane: [TerminalSurfaceID: RemotePaneAgentStatus] = [:]

    private var sessions: [String: HostSession] = [:]

    /// The font every remote pane draws with. Mirrored from the terminal
    /// preferences so a screen from another Mac lines up with the local
    /// panes beside it; kept here because remote panes live in several
    /// windows and this is the one object that knows all of them.
    private(set) var paneFont: NSFont

    init(
        store: RemoteHostStore,
        paneFont: NSFont,
        onError: @escaping (Error) -> Void
    ) {
        self.store = store
        self.paneFont = paneFont
        self.onError = onError
    }

    func update(paneFont: NSFont) {
        guard paneFont != self.paneFont else { return }
        self.paneFont = paneFont
        for session in sessions.values {
            for registration in session.panes.values {
                registration.view?.update(font: paneFont)
            }
        }
    }

    /// Resolves the terminal font preferences into a concrete font, falling
    /// back to the system monospaced face when the configured family is
    /// missing (a font can be uninstalled after it was chosen).
    static func font(for preferences: TerminalPreferences) -> NSFont {
        let size = CGFloat(preferences.fontSize)
        if !preferences.fontFamily.isEmpty,
           let font = NSFont(name: preferences.fontFamily, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Hosts

    func hosts() -> [PairedMac] {
        do {
            return try store.load()
        } catch {
            onError(error)
            return []
        }
    }

    func host(id: String) -> PairedMac? {
        hosts().first { $0.deviceID == id }
    }

    @discardableResult
    func addHost(_ host: PairedMac) -> [PairedMac] {
        do {
            return try store.add(host)
        } catch {
            onError(error)
            return hosts()
        }
    }

    @discardableResult
    func removeHost(id: String) -> [PairedMac] {
        // Drop the live session first: leaving it up would keep mirroring a
        // Mac whose credentials the user just deleted.
        disconnectSession(hostID: id)
        do {
            return try store.remove(id: id)
        } catch {
            onError(error)
            return hosts()
        }
    }

    @discardableResult
    func renameHost(id: String, name: String) -> [PairedMac] {
        do {
            let hosts = try store.rename(id: id, name: name)
            if let renamed = hosts.first(where: { $0.deviceID == id }) {
                sessions[id]?.panes.values.forEach {
                    $0.view?.update(hostName: renamed.displayName)
                }
            }
            return hosts
        } catch {
            onError(error)
            return hosts()
        }
    }

    /// The panes a host currently offers, for the "open remote pane"
    /// picker, grouped by the tab they belong to. Empty until a session to
    /// that host is connected.
    func availablePaneGroups(hostID: String) -> [RemotePanePickerGroup] {
        guard let snapshot = sessions[hostID]?.client.snapshot else { return [] }
        return RemotePanePickerGroup.groups(in: snapshot)
    }

    /// Opens (or reuses) a session to a host without attaching a pane, so
    /// the picker has a snapshot to list. `onSnapshot` fires on every
    /// snapshot while the browse session is up.
    func browse(hostID: String, onSnapshot: @escaping () -> Void) {
        guard let host = host(id: hostID) else { return }
        let session = ensureSession(for: host)
        session.client.$snapshot
            .receive(on: RunLoop.main)
            .sink { _ in onSnapshot() }
            .store(in: &sessions[hostID]!.observers)
        if session.client.state == .disconnected {
            session.client.connect(mac: host)
        }
    }

    func connectionState(hostID: String) -> RemoteClient.ConnectionState {
        sessions[hostID]?.client.state ?? .disconnected
    }

    // MARK: - Panes

    /// Attaches a pane view to its host's session, opening the session if
    /// this is the first pane onto that Mac.
    func attach(_ view: RemotePaneView) {
        guard let host = host(id: view.hostID) else {
            // The host's record is gone (removed in Settings while the pane
            // was open). Leave the pane readable but permanently offline
            // rather than silently retrying against nothing.
            view.update(state: .failed("This Mac is no longer paired"))
            return
        }
        let session = ensureSession(for: host)
        sessions[view.hostID]?.panes[view.paneID] = RemotePaneRegistration(
            remotePaneID: view.remotePaneID,
            view: view
        )

        view.update(hostName: host.displayName)
        view.update(state: session.client.state)
        view.onSendText = { [weak self] text in
            self?.sessions[view.hostID]?.client.sendInput(
                paneID: view.remotePaneID,
                text: text,
                pressEnter: false
            )
        }
        view.onSendKey = { [weak self] key, modifiers in
            self?.sessions[view.hostID]?.client.sendKey(
                paneID: view.remotePaneID,
                key: key,
                modifiers: modifiers
            )
        }
        view.onSendScroll = { [weak self] delta in
            self?.sessions[view.hostID]?.client.sendScroll(
                paneID: view.remotePaneID,
                deltaY: delta
            )
        }
        view.onReconnect = { [weak self] in
            self?.reconnect(hostID: view.hostID)
        }

        if session.client.isConnected {
            session.client.watchPane(view.remotePaneID)
            deliver(hostID: view.hostID)
        } else if session.client.state == .disconnected {
            session.client.connect(mac: host)
        }
    }

    /// Detaches a pane and, once a host has no panes left, closes its
    /// session.
    func detach(paneID: TerminalSurfaceID, hostID: String) {
        guard var session = sessions[hostID] else { return }
        guard let registration = session.panes.removeValue(forKey: paneID)
        else { return }
        agentStatusByPane[paneID] = nil
        sessions[hostID] = session
        if session.client.isConnected {
            session.client.unwatchPane(registration.remotePaneID)
        }
        if session.panes.isEmpty {
            disconnectSession(hostID: hostID)
        }
    }

    func reconnect(hostID: String) {
        guard let host = host(id: hostID) else { return }
        sessions[hostID]?.client.connect(mac: host)
    }

    /// Pastes into a remote pane, which the host frames as a bracketed
    /// paste rather than as typed input.
    func paste(_ text: String, into view: RemotePaneView) {
        guard !text.isEmpty,
              text.utf8.count <= Self.maxPasteBytes
        else { return }
        sessions[view.hostID]?.client.sendInput(
            paneID: view.remotePaneID,
            text: text,
            pressEnter: false,
            paste: true
        )
    }

    /// The transport rejects frames over 1 MB (`RemoteFrameCodec`), and a
    /// paste that large would kill the connection — cap well below. An
    /// oversized clipboard is dropped whole rather than truncated: a
    /// partially pasted command is worse than nothing.
    static let maxPasteBytes = 256 * 1024

    // MARK: - Session plumbing

    private func ensureSession(for host: PairedMac) -> HostSession {
        if let existing = sessions[host.deviceID] { return existing }
        // No push provider: Attention pushes are an iOS concern, and a Mac
        // client has no APNs registration to hand the host.
        let client = RemoteClient()
        var session = HostSession(client: client)
        client.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.apply(state: state, hostID: host.deviceID)
            }
            .store(in: &session.observers)
        client.$paneContent
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.deliver(hostID: host.deviceID)
            }
            .store(in: &session.observers)
        client.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySnapshot(hostID: host.deviceID)
            }
            .store(in: &session.observers)
        sessions[host.deviceID] = session
        return session
    }

    private func disconnectSession(hostID: String) {
        guard let session = sessions.removeValue(forKey: hostID) else { return }
        session.client.disconnect()
    }

    private func apply(state: RemoteClient.ConnectionState, hostID: String) {
        guard let session = sessions[hostID] else { return }
        for registration in session.panes.values {
            registration.view?.update(state: state)
        }
        guard state == .connected else { return }
        // A reconnect leaves the panes on screen, but the host forgot every
        // watch along with the old connection and has to be told again.
        for registration in session.panes.values {
            session.client.watchPane(registration.remotePaneID)
        }
    }

    private func deliver(hostID: String) {
        guard let session = sessions[hostID] else { return }
        for registration in session.panes.values {
            registration.view?.update(
                screen: session.client.paneContent[registration.remotePaneID]
            )
        }
    }

    private func applySnapshot(hostID: String) {
        guard let session = sessions[hostID],
              session.client.isConnected,
              let snapshot = session.client.snapshot
        else { return }
        for (paneID, registration) in session.panes {
            guard let view = registration.view else { continue }
            guard let pane = snapshot.pane(withID: registration.remotePaneID)
            else {
                view.markClosedOnHost()
                agentStatusByPane[paneID] = nil
                continue
            }
            // The pane's own name outranks the tab title it shares with
            // its siblings — the mirror should say which pane it is.
            view.update(title: pane.resolvedName ?? pane.title)
            agentStatusByPane[paneID] = pane.agent
            view.update(agent: pane.agent)
        }
        onAgentStatusChanged?()
    }

    /// Fired after each snapshot so the owning window can refresh a status
    /// bar that is showing a remote pane's agent.
    var onAgentStatusChanged: (() -> Void)?

    func agentStatus(
        forPane paneID: TerminalSurfaceID
    ) -> RemotePaneAgentStatus? {
        agentStatusByPane[paneID]
    }
}
