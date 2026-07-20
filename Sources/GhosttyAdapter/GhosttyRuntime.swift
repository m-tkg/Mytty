import AppKit
import GhosttyKit

public enum GhosttyRuntimeError: Error, Equatable, Sendable {
    case creationFailed
}

public enum GhosttyColorScheme: Equatable, Sendable {
    case light
    case dark
}

@MainActor
public final class GhosttyRuntime {
    private var configuration: GhosttyConfiguration
    private var native: ghostty_app_t?

    public var isRunning: Bool {
        native != nil
    }

    public init(configuration: GhosttyConfiguration) throws {
        self.configuration = configuration

        var runtimeConfiguration = ghostty_runtime_config_s()
        runtimeConfiguration.userdata = Unmanaged
            .passUnretained(self)
            .toOpaque()
        runtimeConfiguration.wakeup_cb = { userdata in
            GhosttyRuntime.scheduleTick(userdata)
        }
        runtimeConfiguration.supports_selection_clipboard = true
        runtimeConfiguration.action_cb = { app, target, action in
            GhosttyRuntime.handleAction(app, target: target, action: action)
        }
        runtimeConfiguration.read_clipboard_cb = { userdata, location, state in
            GhosttyRuntime.readClipboard(
                userdata,
                location: location,
                state: state
            )
        }
        runtimeConfiguration.confirm_read_clipboard_cb = {
            userdata, string, state, request in
            GhosttyRuntime.confirmClipboardRead(
                userdata,
                string: string,
                state: state,
                request: request
            )
        }
        runtimeConfiguration.write_clipboard_cb = {
            userdata, location, content, length, confirm in
            GhosttyRuntime.writeClipboard(
                userdata,
                location: location,
                content: content,
                length: length,
                confirm: confirm
            )
        }
        runtimeConfiguration.close_surface_cb = { userdata, processAlive in
            GhosttyRuntime.closeSurface(userdata, processAlive: processAlive)
        }

        guard let native = ghostty_app_new(
            &runtimeConfiguration,
            configuration.native
        ) else {
            throw GhosttyRuntimeError.creationFailed
        }

        self.native = native
    }

    isolated deinit {
        if let native {
            ghostty_app_free(native)
        }
    }

    func withNative<T>(_ body: (ghostty_app_t) throws -> T) rethrows -> T? {
        guard let native else { return nil }
        return try body(native)
    }

    var nativeApp: ghostty_app_t? {
        native
    }

    public func tick() {
        guard let native else { return }
        ghostty_app_tick(native)
    }

    public func setFocused(_ focused: Bool) {
        guard let native else { return }
        ghostty_app_set_focus(native, focused)
    }

    public func updateConfiguration(_ configuration: GhosttyConfiguration) {
        guard let native else { return }
        self.configuration = configuration
        ghostty_app_update_config(native, configuration.native)
    }

    public func setColorScheme(_ colorScheme: GhosttyColorScheme) {
        guard let native else { return }
        switch colorScheme {
        case .light:
            ghostty_app_set_color_scheme(native, GHOSTTY_COLOR_SCHEME_LIGHT)
        case .dark:
            ghostty_app_set_color_scheme(native, GHOSTTY_COLOR_SCHEME_DARK)
        }
    }

    nonisolated private static func scheduleTick(
        _ userdata: UnsafeMutableRawPointer?
    ) {
        guard let userdata else { return }
        let runtime = Unmanaged<GhosttyRuntime>
            .fromOpaque(userdata)
            .takeUnretainedValue()

        DispatchQueue.main.async {
            runtime.tick()
        }
    }

    nonisolated private static func handleAction(
        _ app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        if action.tag == GHOSTTY_ACTION_CONFIG_CHANGE {
            return true
        }

        if action.tag == GHOSTTY_ACTION_QUIT {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return true
        }

        guard let view = surfaceView(for: target) else { return false }

        switch action.tag {
        case GHOSTTY_ACTION_NEW_TAB:
            DispatchQueue.main.async { view.receiveNewTabRequest() }
            return true

        case GHOSTTY_ACTION_CLOSE_TAB:
            guard action.action.close_tab_mode
                    == GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS
            else { return false }
            DispatchQueue.main.async { view.receiveCloseTabRequest() }
            return true

        case GHOSTTY_ACTION_NEW_WINDOW:
            DispatchQueue.main.async { view.receiveNewWindowRequest() }
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            DispatchQueue.main.async { view.receiveCloseWindowRequest() }
            return true

        case GHOSTTY_ACTION_SET_TITLE:
            guard let pointer = action.action.set_title.title else { return false }
            let title = String(cString: pointer)
            DispatchQueue.main.async { view.receiveTitle(title) }
            return true

        case GHOSTTY_ACTION_PWD:
            guard let pointer = action.action.pwd.pwd else { return false }
            let path = String(cString: pointer)
            DispatchQueue.main.async { view.receiveWorkingDirectory(path) }
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            let value = action.action.cell_size
            DispatchQueue.main.async {
                view.receiveCellSize(width: value.width, height: value.height)
            }
            return true

        case GHOSTTY_ACTION_RENDERER_HEALTH:
            let healthy = action.action.renderer_health
                == GHOSTTY_RENDERER_HEALTH_HEALTHY
            DispatchQueue.main.async { view.receiveRendererHealth(healthy) }
            return true

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            let value = action.action.command_finished
            let exitCode = value.exit_code >= 0
                ? Int(value.exit_code)
                : nil
            DispatchQueue.main.async {
                view.receiveCommandFinished(
                    exitCode: exitCode,
                    durationNanoseconds: value.duration
                )
            }
            return true

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            let value = action.action.child_exited
            DispatchQueue.main.async {
                view.receiveChildExit(
                    code: value.exit_code,
                    runtimeMilliseconds: value.timetime_ms
                )
            }
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            let value = action.action.open_url
            guard let pointer = value.url else { return false }
            let bytes = UnsafeRawPointer(pointer)
                .assumingMemoryBound(to: UInt8.self)
            let urlString = String(
                decoding: UnsafeBufferPointer(
                    start: bytes,
                    count: Int(value.len)
                ),
                as: UTF8.self
            )
            guard let url = URL(string: urlString) else { return false }
            DispatchQueue.main.async {
                view.receiveOpenURLRequest(url)
            }
            return true

        case GHOSTTY_ACTION_START_SEARCH:
            let pointer = action.action.start_search.needle
            let needle = pointer.map(String.init(cString:))
            DispatchQueue.main.async {
                view.receiveStartSearch(needle)
            }
            return true

        case GHOSTTY_ACTION_END_SEARCH:
            DispatchQueue.main.async { view.receiveEndSearch() }
            return true

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let value = action.action.search_total.total
            let total = value >= 0 ? Int(value) : nil
            DispatchQueue.main.async { view.receiveSearchTotal(total) }
            return true

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let value = action.action.search_selected.selected
            let selected = value >= 0 ? Int(value) : nil
            DispatchQueue.main.async {
                view.receiveSearchSelected(selected)
            }
            return true

        default:
            return false
        }
    }

    nonisolated private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let view = surfaceView(from: userdata) else { return false }
        let stateAddress = state.map(UInt.init(bitPattern:))
        return MainActor.assumeIsolated {
            view.readClipboard(
                location: location,
                state: stateAddress.flatMap(UnsafeMutableRawPointer.init(bitPattern:))
            )
        }
    }

    nonisolated private static func confirmClipboardRead(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let view = surfaceView(from: userdata) else { return }
        let value = string.map(String.init(cString:)) ?? ""
        let stateAddress = state.map(UInt.init(bitPattern:))
        MainActor.assumeIsolated {
            view.confirmClipboardRead(
                value,
                state: stateAddress.flatMap(
                    UnsafeMutableRawPointer.init(bitPattern:)
                ),
                request: request
            )
        }
    }

    nonisolated private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        length: Int,
        confirm: Bool
    ) {
        guard !confirm,
              let view = surfaceView(from: userdata),
              let content,
              length > 0
        else { return }
        let items = (0..<length).compactMap { index -> ClipboardItem? in
            guard let mime = content[index].mime,
                  let data = content[index].data
            else { return nil }
            return ClipboardItem(
                mime: String(cString: mime),
                data: String(cString: data)
            )
        }
        MainActor.assumeIsolated {
            view.writeClipboard(
                location: location,
                items: items
            )
        }
    }

    nonisolated private static func closeSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        guard let view = surfaceView(from: userdata) else { return }
        DispatchQueue.main.async {
            view.receiveCloseRequest(processAlive: processAlive)
        }
    }

    nonisolated private static func surfaceView(
        for target: ghostty_target_s
    ) -> GhosttySurfaceView? {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface
        else { return nil }
        return surfaceView(from: ghostty_surface_userdata(surface))
    }

    nonisolated private static func surfaceView(
        from userdata: UnsafeMutableRawPointer?
    ) -> GhosttySurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttySurfaceView>
            .fromOpaque(userdata)
            .takeUnretainedValue()
    }
}

struct ClipboardItem: Sendable {
    let mime: String
    let data: String
}
