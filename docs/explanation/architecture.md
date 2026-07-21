# Architecture

日本語版は [architecture_ja.md](architecture_ja.md) にあります。

This page explains the shape of Mytty and why it is built the way it is: a native terminal that delegates emulation to libghostty and layers agent-awareness on top, without introducing a workspace abstraction or a chat-style orchestration UI.

## What Mytty is, and is not

Mytty is a macOS-only, native terminal built for AI-assisted workflows. It delegates terminal emulation, PTY management, and Metal rendering to libghostty, and adds an agent-aware Attention Inbox on top. It supports Codex, Claude Code, OpenCode, Gemini (Antigravity), and Cursor.

The deliberate choice is what Mytty does *not* add: no workspace or project entity, no chat panel, no orchestration engine that runs agents on the app's behalf. An agent is just a foreground process in a pane, observed through events; the terminal itself stays the primary surface. This keeps the app useful even for panes that never run an agent at all, and it avoids the maintenance burden of a second, competing model of "what an agent session is" alongside the one each provider already has.

## User model

The object hierarchy is intentionally shallow:

```text
Window
`-- Tab
    `-- SplitNode
        `-- TerminalSurface
            `-- AgentRun
```

There is no workspace entity above the window. Current directory, Git branch, foreground process, and agent state are all properties of a terminal surface, not of some larger project object. This mirrors how a terminal is actually used day to day: someone opens panes for whatever they are doing right now, not for a project they set up in advance. Vertical tabs are the default (horizontal is available in Settings), and both multiple windows and nested splits are supported, but nothing above `TerminalSurface` tries to remember why those panes exist together.

## UI ownership

AppKit and SwiftUI each own a distinct slice of the app, and the split follows where precision matters most:

- AppKit owns windows, menus, focus, keyboard routing, IME, and the terminal hosts themselves. Keystroke latency and IME correctness are not things to risk on a SwiftUI re-render cycle.
- SwiftUI owns Settings, the tab sidebar, and the Attention drawer, where declarative layout is worth more than raw control.
- Settings apply immediately unless a change explicitly requires a restart, so the settings surface never becomes a place users have to remember to come back to.
- The Attention drawer opens on the right and never grabs focus or opens itself unprompted; an agent finishing work in the background should not be able to interrupt whatever the user is doing in the foreground pane.

## Target boundaries

The SwiftPM package (`Package.swift`) enforces the architecture with real target boundaries, not just convention:

- **`MyTTYApp`** is the macOS app. `TerminalWindowController` is the hub for a window: it owns per-concern collaborators (`AgentStatusPollingCoordinator`, `AgentUsagePollingCoordinator`, `RepositoryStatusCoordinator`, `PaneLayoutController`, `TerminalAutocompleteCoordinator`, `TerminalRecordingCoordinator`, `ScheduledInputCoordinator`, `RemotePaneBridge`, `TabDragController`) and wires their output into surfaces and the status bar, rather than doing all of that inline. `AppDelegate` delegates the same way at the app level: menu construction goes to `MainMenuBuilder`, window and session lifecycle to `WindowSessionCoordinator`, update checks to `ApplicationUpdateCoordinator`, and the remote-access server delegate to `RemoteAccessCoordinator`. Splitting a god-object controller into named coordinators is what keeps each concern testable and lets a change to, say, agent usage polling land without touching pane layout.
- **`GhosttyAdapter`** is the only target allowed to touch Ghostty types. libghostty is pinned to an exact source revision and built as an XCFramework with an unversioned C API, so every call into it is quarantined behind this one adapter boundary. Keyboard input, IME, resize, and rendering must not pass through global SwiftUI or observable app state; those paths need to stay as direct and low-latency as libghostty itself.
- **`MyTTYCore`** holds platform-neutral logic built on Foundation only: the tab/session model (`TabSession`, `SessionSnapshot`), the agent event protocol and its reducers, SQLite repositories, preferences, and the provider-specific `*SessionInspector` / `*UsageProbe` implementations plus `AgentSessionDatabase`. Keeping this Foundation-only is what lets it run in tests without an AppKit environment.
- **`MyTTYAgentHook`** is the `mytty-agent-hook` helper binary that provider hooks invoke; it forwards events to the app over the socket described below.
- **`MyTTYClamshellHelper`** is the `mytty-clamshell-helper` privileged daemon (SMAppService/XPC) that runs `pmset disablesleep` for lid-closed keep-awake; its state machine (`ClamshellHelperCore`) lives in `MyTTYCore` so it can be tested without the privileged helper actually running.
- **`MyTTYRemoteKit`** is shared code for the iOS remote app (pairing, secure channel).

Every entry point into the app (menu commands, keyboard shortcuts, the CLI, and the `mytty-ctl` control socket) ends up calling the same application-level commands on `TerminalWindowController` and `WindowSessionCoordinator` rather than each having its own path to mutate state. That convergence is what keeps "a pane opened from a menu item" and "a pane opened by `mytty-ctl split`" behave identically instead of drifting apart over time.

## Agent events: why not scrape the screen

Agent state is derived from versioned, idempotent events delivered by explicit hooks or by libghostty's own terminal protocol support (see `docs/reference/agent-event-protocol.md` for the wire format). Human-readable terminal output is never parsed to infer state. This rules out the tempting shortcut of regexing an agent's CLI output for phrases like "Waiting for approval": that text changes across provider versions and locales without notice, and a false read would either spam the Attention Inbox or silently drop a real approval request. Events are the only source that can carry a stable schema version. Where no integration reports anything, run state stays `unknown` rather than being guessed.

```text
unknown -> running
running -> waitingInput | waitingApproval | succeeded | failed
waitingInput | waitingApproval -> running
any -> disconnected
```

The append-only event log is the source of truth; a pure reducer derives the current run state from it, and Attention policy derives actionable items from that state. Keeping the reducer pure (no side effects, no hidden state) is what makes the state machine above testable as a table of inputs and outputs rather than something that only breaks in the running app.

## Attention Inbox

The Inbox surfaces exactly four kinds of event: approval requests, input requests, failures or disconnects, and completion of long-running work. Everything else about a pane, routine output and progress logs included, stays out of it on purpose, because an inbox that also reports "still running" stops being something worth checking.

An event creates a tab badge; a macOS notification fires only when the tab is not currently visible, so a user actively watching a pane is never also interrupted by a notification for the same event. Inbox actions are limited to Focus and Acknowledge. Replying to a prompt or approving a request happens in the terminal itself, not through a second control surface that could get out of sync with what the agent actually sees. Resolved items are retained for 24 hours so a quick glance back is possible without turning the Inbox into a permanent log.

## Agent integration: hooks, not polling alone

Settings provides one-click, reversible installation and removal of hooks for each supported provider, writing into that provider's own global config (`~/.codex/hooks.json`, `~/.claude/settings.json`, and so on). Installers preserve unrelated user configuration and write atomically. Users bring their own provider configs, and an installer that clobbered unrelated keys or left a half-written file on crash would be a much worse failure mode than events not showing up.

Hooks send events over a user-only Unix socket, and each pane's hook receives a capability scoped to that pane alone. Input injection and screen capture are deliberately separate capabilities that event hooks are never granted, so a compromised or misbehaving hook script can report state but cannot act on the terminal.

Hooks alone cannot cover everything a status bar wants to show, so `TerminalWindowController`'s `AgentStatusPollingCoordinator` complements them by polling each pane's foreground process every 0.5 seconds. It detects the provider from the executable and arguments (`TerminalAgentProcessDetector`), resolves that provider's `AgentProviderRuntime` (one implementation per provider, registered in `AgentProviderRuntimeRegistry`), and reads the in-use model and remaining context through that provider's `*SessionInspector`, which parses Codex transcript file descriptors, Claude Code project transcripts, OpenCode and Cursor SQLite databases, or Antigravity settings, depending on the provider. Because this runs on the main thread, it is throttled and fingerprint-cached (`AgentSessionThrottleCache`) rather than re-parsing on every tick. `AgentUsagePollingCoordinator` loads quota and cost meters the same way, through `NativeAgentUsageLoader` and the parallel `AgentProviderUsageSource` registry over each provider's `*UsageProbe`.

`AgentSessionDatabase` in `MyTTYCore` is the shared read-only SQLite helper behind these probes; it falls back to an `immutable=1` connection when a WAL database's sidecar files were checkpointed away. Code that needs to read a provider's SQLite state reuses this rather than opening SQLite directly, since the WAL fallback is exactly the kind of detail that is easy to get wrong once and then debug twice.

## Configuration and state

User configuration is controlled through the UI and stored at:

```text
~/.config/mytty/config.toml
~/.config/mytty/terminal.conf
~/.config/mytty/agents.toml
```

`terminal.conf` is passed straight to libghostty. Importing an existing Ghostty config is an explicit, one-time action rather than an implicit second source of truth that Mytty would otherwise have to keep in sync with its own config forever.

Runtime state lives separately from configuration:

```text
~/Library/Application Support/mytty/mytty.sqlite
~/Library/Logs/mytty/mytty.log
$TMPDIR/mytty.sock
```

Windows, tabs, split layout, and current directories are restored across relaunches; scrollback persistence is opt-in and off by default, and arbitrary live processes are not restored. Debug builds run as **Mytty Dev** and isolate all of the above under `~/.config/mytty-dev/` and its Application Support / log equivalents, specifically so a development build can never disturb an installed release's sessions or sockets.

## CLI and control socket

The same application commands are reachable from a local CLI and socket API (`mytty list --json`, `mytty tab new`, `mytty split --right`, `mytty focus <surface-id>`, `mytty event emit <event>`, `mytty config validate`/`reload`, and more). This is also the foundation for `mytty-ctl`, the AI-facing control CLI that lets an agent running in one pane drive other panes as a visible, interruptible team. See [mytty-ctl-architecture.md](mytty-ctl-architecture.md) for why that is built as a plain local socket with no pairing or encryption.

## What changed since the original design

Mytty's original design document listed an embedded browser under initial non-goals, alongside workspace orchestration and inbox-based replies. The browser pane (`BrowserPaneView.swift`) shipped since then. It turned out to be useful enough for viewing local HTML and web content alongside a terminal that it was worth building, and it lives in the same pane/split model as terminal surfaces rather than as a separate concept. The other non-goals (workspace orchestration, inbox-based replies and approvals, output heuristics for agent state, a persistent PTY daemon, cloud sync) still hold as of this writing. The staged delivery plan the original design laid out, surface first, then tabs and persistence, then agent events, then UI and hook installers, then CLI and packaging, has already run its course. The sections above describe where that plan landed rather than where it is headed.
