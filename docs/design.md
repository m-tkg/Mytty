# Mytty Design

Status: Accepted for implementation

## Product

Mytty is a macOS-only, native terminal. It delegates terminal emulation, PTY
management, and Metal rendering to libghostty and adds an agent-aware Attention
Inbox without replacing the terminal with a chat or orchestration UI.

The initial application supports Codex, Claude Code, OpenCode, Gemini
(Antigravity), and Cursor. It is built for personal use first, but its
interfaces, tests, and packaging should remain suitable for a public
MIT-licensed release.

## User model

The hierarchy is intentionally small:

```text
Window
`-- Tab
    `-- SplitNode
        `-- TerminalSurface
            `-- AgentRun
```

There is no workspace entity. Current directory, Git branch, foreground
process, and agent state are properties associated with a terminal surface.

Vertical tabs are the default. Horizontal tabs are available through Settings.
Multiple windows and nested horizontal or vertical splits are supported.

## UI

- AppKit owns windows, menus, focus, keyboard routing, IME, and terminal hosts.
- SwiftUI owns Settings, the tab sidebar, and the Attention drawer.
- Settings apply immediately unless a setting explicitly requires restart.
- Agent state is shown on tabs with an icon and color-independent label or
  accessibility value.
- Attention opens as a right-side drawer and never opens or changes focus
  automatically.

## Architecture

```text
UI and CLI
`-- AppCommandBus
    |-- TabSessionCore
    |-- GhosttyAdapter
    |-- AgentIntegration
    |-- AttentionReducer
    |-- SessionRepository
    `-- ControlServer
```

All entry points call the same application commands. Ghostty types remain
inside GhosttyAdapter. Keyboard input, IME, resize, and rendering must not pass
through global SwiftUI or observable application state.

libghostty is pinned to an exact source revision and built as an XCFramework.
The adapter boundary absorbs its currently unversioned C API.

## Agent events

Agent state is derived from versioned, idempotent events delivered by explicit
agent hooks or standard terminal protocols. Human-readable output is never
parsed to infer state. Missing integration data produces `unknown`.

```text
unknown -> running
running -> waitingInput | waitingApproval | succeeded | failed
waitingInput | waitingApproval -> running
any -> disconnected
```

The append-only event log is the source of truth. A pure reducer derives the
current run state. Attention policy derives actionable items from that state.

## Attention Inbox

The Inbox includes only:

1. Approval requests.
2. Input requests.
3. Failures or disconnects.
4. Completion of long-running work.

An event creates a tab badge. A macOS notification is sent only when its tab is
not visible. Inbox actions in the initial release are Focus and Acknowledge;
reply and approval controls remain in the terminal. Resolved items are retained
for 24 hours.

## Agent integration

Settings provides explicit, reversible one-click installation and removal of
hooks for Codex, Claude Code, OpenCode, Gemini (Antigravity), and Cursor.
Installers preserve unrelated user configuration and use atomic writes.

Hooks send events over a user-only Unix socket. Each terminal receives a
capability scoped to its own surface. Input injection and screen capture are
separate capabilities and are not granted to event hooks.

## Configuration and state

User configuration is controlled through UI and stored at:

```text
~/.config/mytty/config.toml
~/.config/mytty/terminal.conf
~/.config/mytty/agents.toml
```

`terminal.conf` is passed to libghostty. Importing an existing Ghostty config is
an explicit action rather than an implicit second source of truth.

Runtime state is separate:

```text
~/Library/Application Support/mytty/mytty.sqlite
~/Library/Logs/mytty/mytty.log
$TMPDIR/mytty.sock
```

Windows, tabs, split layout, and current directories are restored. Scrollback
persistence is opt-in and disabled by default. Arbitrary live processes are not
restored in the initial release.

## CLI

The initial local CLI and socket API support:

```text
mytty list --json
mytty tab new
mytty split --right
mytty focus <surface-id>
mytty event emit <event>
mytty config validate
mytty config reload
```

## Initial non-goals

- Workspace or project orchestration.
- Embedded browser.
- Inbox-based replies or approvals.
- Output heuristics for agent state.
- Persistent PTY daemon.
- Cloud sync, managed SSH, or automatic Git worktrees.

## Delivery stages

1. Prove one libghostty surface in an AppKit view, including Japanese IME,
   resize, copy/paste, configuration, title, cwd, and child-exit callbacks.
2. Add the tested tab and split domain model and session persistence.
3. Add versioned agent events, adapters, state reduction, and Attention policy.
4. Add vertical and horizontal tab UI, split controls, Attention drawer, native
   Settings, and hook installers.
5. Add the CLI and release packaging.

The first stage is a hard gate. Product features do not build on a terminal
surface that has not passed the input, rendering, focus, and lifecycle checks.
