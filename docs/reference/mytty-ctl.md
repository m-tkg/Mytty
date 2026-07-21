# mytty-ctl reference

`mytty-ctl` is the local CLI a coding agent (Claude Code, Codex, Cursor,
...) uses to drive Mytty itself. It creates and splits panes, sends
text and key presses, reads a pane's screen, and waits for an agent
run to go idle or need attention. It talks to `ControlServer`
(`MyTTYApp`) over a Unix-domain socket restricted to the current user,
one JSON request per connection, and is a separate transport from the
iOS remote (`RemoteAccessServer`, TCP with pairing and encryption).
Source: `Sources/MyTTYCore/ControlProtocol.swift`,
`Sources/MyTTYCore/ControlCommandLineParser.swift`,
`Sources/MyTTYApp/ControlServer.swift`,
`Sources/MyTTYApp/ControlCoordinator.swift`.

## Environment variables

Every pane Mytty opens gets these three variables set automatically
(`AgentEventServer.environment(for:)`), so no setup is required before
calling `mytty-ctl` from inside a pane:

| Variable | Meaning |
| --- | --- |
| `MYTTY_CONTROL_SOCKET` | Absolute path of the Unix socket `mytty-ctl` connects to |
| `MYTTY_CTL_BIN` | Absolute path of the `mytty-ctl` binary (no `PATH` entry required) |
| `MYTTY_SURFACE_ID` | This pane's own pane ID, usable as the "self" pane in commands |

```bash
"$MYTTY_CTL_BIN" split "$MYTTY_SURFACE_ID" right --cwd /path/to/worktree
```

If `mytty-ctl` is on `PATH`, invoking it by name works the same way. A
debug build (`Mytty Dev`) and a release build each expose their own
socket under separate `~/.config/mytty(-dev)` directories.
`mytty-ctl` itself is unaware of which one it is talking to; that is
entirely determined by which pane's environment it inherited.

## Exit status and output

Every command prints exactly one line of JSON to stdout and exits `0` on
success. On failure it prints a message to stderr and exits `1`.

```bash
mytty-ctl list | jq .
```

## Commands

| Command | Arguments | Success response |
| --- | --- | --- |
| `list` | none | `{"type":"list","panes":[...]}` |
| `new-tab` | `[--cwd <path>]` | `{"type":"pane","paneID":"..."}` |
| `split` | `<pane-id> <left\|right\|up\|down> [--cwd <path>]` | `{"type":"pane","paneID":"..."}` |
| `send` | `<pane-id> <text> [--enter]` | `{"type":"ok"}` |
| `send-key` | `<pane-id> <key> [--modifiers <mod,mod,...>]` | `{"type":"ok"}` |
| `read` | `<pane-id>` | `{"type":"content","content":{...}}` |
| `wait` | `<pane-id> --until <idle\|attention> [--timeout-seconds <n>]` | `{"type":"waitResult","state":"...","timedOut":false}` |
| `close-pane` | `<pane-id>` | `{"type":"ok"}` |
| `focus` | `<pane-id>` | `{"type":"ok"}` |

pane IDs are the UUID string form of `TerminalSurfaceID`. Get one from a
`list` response, a `pane` response, or `$MYTTY_SURFACE_ID`.

### list

Lists every pane across every open window.

```bash
mytty-ctl list
```

![`mytty-ctl list | jq .` run from inside a Mytty pane with no agent history](../images/mytty-ctl-list.png)

```json
{
  "type": "list",
  "panes": [
    {
      "paneID": "B9AA8B83-B42D-4C11-B838-36B84C73032A",
      "windowID": "...",
      "tabID": "...",
      "title": "zsh",
      "command": "zsh",
      "workingDirectory": "/Users/me/project",
      "isActive": true,
      "provider": "codex",
      "agentState": "running"
    }
  ]
}
```

`provider` is an `AgentProvider.rawValue` (see
[Agent event protocol](agent-event-protocol.md)) and `agentState` an
`AgentRunState.rawValue`. Both keys are omitted from the JSON entirely
until at least one agent event has been recorded for that pane (verified
against a live `mytty-ctl list | jq .` run on a pane with no agent
history: no `provider` or `agentState` key appears at all).

### new-tab

Creates a new tab in the active window (or the first window found, if
none is active). There is no way to target a specific window; split an
existing pane in that window instead.

```bash
mytty-ctl new-tab --cwd /path/to/project
```

```json
{ "type": "pane", "paneID": "..." }
```

`--cwd` defaults to the active window's current working directory when
omitted.

### split

Splits an existing pane in the given direction, focusing the target pane
first.

```bash
mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd /tmp
```

```json
{ "type": "pane", "paneID": "..." }
```

### send

Types text into a pane, optionally followed by Return.

```bash
mytty-ctl send "$paneA" "claude" --enter
mytty-ctl send "$paneA" "investigate issue #42" --enter
```

```json
{ "type": "ok" }
```

### send-key

Sends a single synthesized key event, for interactive prompts that don't
respond to plain text (arrow-key menus, `Esc` to cancel, ...).

```bash
mytty-ctl send-key "$paneA" escape
mytty-ctl send-key "$paneA" up
mytty-ctl send-key "$paneA" c --modifiers control
```

Recognized `<key>` values (`RemoteKeyMapping.swift`):

| Category | Values |
| --- | --- |
| Named keys | `escape`, `tab`, `return`, `delete`, `space`, `up`, `down`, `left`, `right`, `f1`-`f12` |
| Single characters | any one of `a`-`z`, `0`-`9`, `` ` ``, `-`, `=`, `[`, `]`, `\`, `;`, `'`, `,`, `.`, `/` |

`--modifiers` takes a comma-separated list drawn from `shift`,
`control`, `option`, `command` (e.g. `--modifiers shift,command`). An
unrecognized `<key>` value fails with the `pane-not-found` error code
even when the pane itself exists. `ControlCoordinator` treats "no key
mapping" and "no such pane" the same way, so the code name is misleading
in this one case. No key event is sent when this happens.

```json
{ "type": "ok" }
```

### read

Reads the pane's current screen content and cursor position.

```bash
mytty-ctl read "$paneA"
```

```json
{
  "type": "content",
  "content": {
    "paneID": "...",
    "text": "$ ls\nREADME.md\n...",
    "cursorRow": 3,
    "cursorColumn": 0
  }
}
```

`cursorRow` and `cursorColumn` are `null` when the pane has no cursor
position to report.

### wait

Blocks until the pane's most relevant agent run satisfies a condition, or
until the timeout elapses.

```bash
mytty-ctl wait "$paneA" --until idle
mytty-ctl wait "$paneA" --until attention --timeout-seconds 600
```

```json
{ "type": "waitResult", "state": "idle", "timedOut": false }
```

`--timeout-seconds` defaults to `120`. `state` is the `AgentRunState`
observed when the wait resolved (or `null` if no event has ever arrived
for that pane); `timedOut` is `true` if the deadline was reached without
the condition being satisfied. See [wait semantics](#wait-semantics)
below.

### close-pane

Closes a pane immediately, with no confirmation dialog. The caller is
assumed to be an automated agent, not a human clicking Close.

```bash
mytty-ctl close-pane "$paneA"
```

```json
{ "type": "ok" }
```

Closing the last pane of the last tab in a window still triggers that
window's own close-confirmation dialog, if the user has one configured;
this case does not normally arise for panes created to run subagents.

### focus

Brings a pane to the foreground, for handing control back to the user.

```bash
mytty-ctl focus "$paneA"
```

```json
{ "type": "ok" }
```

## Failure responses

A failed request returns `{"type":"failure","code":"..."}` from the
server; the CLI surfaces this as a non-zero exit with a stderr message
rather than printing the JSON.

| Code | Meaning |
| --- | --- |
| `invalid-request` | The request could not be decoded as JSON, or malformed argument syntax at the CLI layer |
| `not-ready` | The control server has no delegate yet (app still starting) |
| `new-tab-failed` | `new-tab` could not create a tab |
| `split-failed` | `split` could not split the given pane |
| `pane-not-found` | The given `pane-id` does not resolve to a live pane (also returned by `send`, `send-key`, `read`, `wait`, `close-pane`, `focus`) |

## Wait semantics

`wait` polls at a fixed interval (roughly 300 ms) until the condition is
met or the deadline passes.

- `--until idle` resolves once the pane's most recent agent run reaches
  `idle`, `succeeded`, `failed`, or `disconnected`. A pane that has never
  received an agent event blocks until timeout; there is no "already
  idle" default.
- `--until attention` resolves once the run reaches `waiting-input` or
  `waiting-approval`. Antigravity's installed hooks never emit approval-
  or input-requested events (see [Agent providers](agent-providers.md)),
  so `wait --until attention` always times out for panes running that
  provider; use `--until idle` for it instead. Cursor never emits
  input-requested either, but it can reach `waiting-approval`: mytty
  estimates a stuck shell approval from a delay between Cursor's
  `beforeShellExecution` and `afterShellExecution` hooks, so `wait
  --until attention` resolves for a Cursor pane once that estimate fires
  (roughly 10 seconds after the command starts, if nothing resolves it
  sooner).
- If the target provider's hook integration has not been enabled yet in
  Settings, no agent events reach Mytty at all and `wait` blocks until
  timeout regardless of condition. This is the most common cause of an
  unexpected timeout the first time a provider is used from a script.

## Constraints

- `new-tab` cannot target a specific window; it always lands in the
  active window, or the first window found if none is active. To open a
  pane in a specific window, `split` one of that window's existing panes
  instead.
- `close-pane` never shows a confirmation dialog. The one exception,
  closing the last pane of the last tab, still triggers the window's own
  close confirmation; this does not normally apply to panes created for
  subagent teams.
- pane IDs are `TerminalSurfaceID` UUID strings, obtained from `list`, a
  `pane` response, or `$MYTTY_SURFACE_ID`.
- The maximum request size accepted by the control socket matches the
  agent-event socket's 64 KiB envelope limit; a very large `send`
  argument should be chunked or piped through the shell instead of
  passed as one oversized literal.

## See also

- [Agent providers](agent-providers.md) covers which providers expose
  approval/input events, relevant to `wait --until attention`.
- [Agent event protocol](agent-event-protocol.md) documents the
  `AgentProvider` and `AgentRunState` values surfaced in `list` and `wait`.
- `.claude/skills/mytty-panes/SKILL.md` has task recipes built on these
  commands.
