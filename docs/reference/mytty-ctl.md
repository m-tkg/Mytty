# mytty-ctl reference

`mytty-ctl` is the local CLI a coding agent (Claude Code, Codex, Cursor, ...) uses to drive Mytty itself. Its `agent` subcommands spawn a worker provider in a new pane, deliver its task as one shell input, and track that exact spawn as a job a lead can wait on, read the result of, and send follow-ups to. The older pane-level commands (`split`, `send`, `wait`, `read`, ...) still work and remain the right tool for driving a pane by hand; the [orchestration how-to](../how-to/orchestrate-agents-with-mytty-ctl.md) covers when to reach for which. It talks to `ControlServer` (`MyTTYApp`) over a Unix-domain socket restricted to the current user, one JSON request per connection, and is a separate transport from the iOS remote (`RemoteAccessServer`, TCP with pairing and encryption). Source: `Sources/MyTTYCore/ControlProtocol.swift`, `Sources/MyTTYCore/ControlCommandLineParser.swift`, `Sources/MyTTYCore/AgentJob.swift`, `Sources/MyTTYCore/AgentLaunchPlan.swift`, `Sources/MyTTYApp/ControlServer.swift`, `Sources/MyTTYApp/ControlCoordinator.swift`, `Sources/MyTTYApp/AgentJobCoordinator.swift`.

## Environment variables

Every pane Mytty opens gets these three variables set automatically (`AgentEventServer.environment(for:)`), which also adds `mytty-ctl`'s directory to `PATH`, so no setup is required before calling `mytty-ctl` by name from inside a pane:

| Variable | Meaning |
| --- | --- |
| `MYTTY_CONTROL_SOCKET` | Absolute path of the Unix socket `mytty-ctl` connects to |
| `MYTTY_CTL_BIN` | Absolute path of the `mytty-ctl` binary (for when invoking it by name isn't reliable) |
| `MYTTY_SURFACE_ID` | This pane's own pane ID, usable as the "self" pane in commands |

```bash
mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd /path/to/worktree
```

A debug build (`Mytty Dev`) and a release build each expose their own socket under separate `~/.config/mytty(-dev)` directories. `mytty-ctl` itself is unaware of which one it is talking to; that is entirely determined by which pane's environment it inherited.

## Using mytty-ctl outside Mytty

The `PATH` entry above only covers panes Mytty itself opened. To call `mytty-ctl` from somewhere else -- another terminal app, a script -- use the "Install CLI" button in Settings > Orchestration. It symlinks the installed binary into `~/.local/bin`, with no admin prompt. If something else already sits at that name (a link pointing elsewhere, or a real file), the button reports a failure instead of silently overwriting it.

If `~/.local/bin` isn't already on your shell's `PATH`, the button shows a line to add after installing:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that to your shell profile (`.zshrc` or similar) and open a new shell, or re-source it, and `mytty-ctl` resolves by name.

A development build (Mytty Dev) installs under a different name, `~/.local/bin/mytty-ctl-dev`, so it never takes over the release build's link.

## Calling mytty-ctl from inside Codex's sandbox

Shell commands Codex runs execute inside a macOS Seatbelt sandbox (`review` or `workspace-write`), so `mytty-ctl` called from there gets `connect(2)` to the Unix domain socket denied outright by the operating system -- every command, including `list` and `agent spawn`, fails with `socketOperation(1)` (`EPERM`). The socket file, its permissions, and `MYTTY_CONTROL_SOCKET` are all fine; the same socket connects normally from outside the sandbox (another pane, a plain shell). If Codex is the lead driving other panes, ask for approval to run `mytty-ctl` commands outside the sandbox. Workers `agent spawn` launches into other panes aren't affected -- they run in their own shell, not the lead's sandbox.

## Exit status and output

Every command prints exactly one line of JSON to stdout and exits `0` on success. On failure it prints a message to stderr and exits `1`.

```bash
mytty-ctl list | jq .
```

## Commands

Prefer the `agent` commands for anything shaped like "run one or more workers and collect their output" -- they cover spawning a worker, waiting on the exact run it started, reading its result, and sending follow-ups, without the races the pane-level commands leave for the caller to avoid by hand (see [Agent job binding](#agent-job-binding) below). The pane-level commands remain the tool for driving a pane manually.

| Command | Arguments | Success response |
| --- | --- | --- |
| `agent spawn` | `--provider <codex\|claude\|cursor> (--task <text>\|--task-file <path>) [--anchor <pane-id>] [--direction <left\|right\|up\|down>] [--cwd <path>] [--access <review\|workspace-write\|inherit>] [--model <text>] [--label <text>]` | `{"type":"agentJob","job":{...}}` |
| `agent wait` | `<job-id> --until <running\|attention\|completed> [--timeout-seconds <n>]` | `{"type":"agentWaitResult","job":{...},"timedOut":false}` |
| `agent result` | `<job-id>` | `{"type":"agentResult","job":{...},"content":{...}}` |
| `agent send` | `<job-id> <text> [--enter]` | `{"type":"ok"}` |
| `agent focus` | `<job-id>` | `{"type":"ok"}` |
| `agent close` | `<job-id>` | `{"type":"ok"}` |
| `guide` | none | pane-team playbook as plain text on stdout, no socket needed |
| `list` | none | `{"type":"list","panes":[...]}` |
| `new-tab` | `[--cwd <path>]` | `{"type":"pane","paneID":"..."}` |
| `split` | `<pane-id> <left\|right\|up\|down> [--cwd <path>]` | `{"type":"pane","paneID":"..."}` |
| `send` | `<pane-id> <text> [--enter]` | `{"type":"ok"}` |
| `send-key` | `<pane-id> <key> [--modifiers <mod,mod,...>]` | `{"type":"ok"}` |
| `read` | `<pane-id>` | `{"type":"content","content":{...}}` |
| `wait` | `<pane-id> --until <idle\|attention> [--timeout-seconds <n>]` | `{"type":"waitResult","state":"...","timedOut":false}` |
| `close-pane` | `<pane-id>` | `{"type":"ok"}` |
| `focus` | `<pane-id>` | `{"type":"ok"}` |

Pane IDs are the UUID string form of `TerminalSurfaceID`. Get one from a `list` response, a `pane` response, or `$MYTTY_SURFACE_ID`. Job IDs are the `{"rawValue":"..."}` UUID form of `AgentJobID`, read from an `agentJob`/`agentWaitResult`/`agentResult` response's `job.jobID.rawValue`.

### agent spawn

Splits a new pane off `--anchor` (default `$MYTTY_SURFACE_ID`) and launches the given provider in it, delivering `--task` (or the contents of `--task-file`, read by `mytty-ctl` itself before the request is sent) as one shell input together with the launch command -- there is no separate `send` that could race the worker's TUI starting up. `--access` defaults to `workspace-write`; `review` launches the provider in its read-only/plan mode instead. `inherit` copies the mode flags of the agent running in the anchor pane -- the lead's own process -- onto the worker's launch command instead of using either fixed flag set: use it when spawning a worker of the same provider as yourself so it runs with your own permission/sandbox mode (e.g. a `claude` lead running `--permission-mode acceptEdits` or `--dangerously-skip-permissions` spawns a `claude` worker with those same flags). It fails with `inherit-unavailable` when the anchor pane's foreground process can't be read at all, or is a different provider than `--provider` -- inheriting flags across providers is meaningless, since they don't share a flag vocabulary. This reads the lead's launch argv, so a mode switched to interactively after launch (Claude Code's shift+tab permission-mode cycling, for instance) is invisible to it; only the flags the lead was actually started with are inherited. If the lead is running in its default mode (no mode-relevant flags in its argv), `inherit` falls back to the same flags `workspace-write` would use. `--model` is optional and picks the provider's model, passed straight through to the provider CLI's own model flag -- `-m <model>` for `codex`, `--model <model>` for `claude` and `cursor` -- e.g. `--model sonnet` for a `claude` worker. Omit it to use whatever model the provider defaults to. `--cwd` defaults to the anchor pane's shell-reported working directory (the last directory the pane's shell announced via shell integration), not the calling process's own cwd. An orchestrator whose process cwd differs from its pane's shell -- for example Claude Code launched with `--worktree`, which chdirs into a git worktree the pane's shell never entered -- should pass `--cwd "$PWD"` explicitly, or its workers start in the original checkout instead of the worktree. A worker contract (stay in the working directory, keep going instead of stopping to ask, end with a concise summary) is appended to every task automatically.

```bash
job=$(mytty-ctl agent spawn \
  --provider codex --access review \
  --task "Investigate why login times out under load." \
  --label investigate-a | jq -r '.job.jobID.rawValue')
```

```json
{
  "type": "agentJob",
  "job": {
    "jobID": { "rawValue": "..." },
    "paneID": { "rawValue": "..." },
    "provider": "codex",
    "label": "investigate-a",
    "state": "launching",
    "runID": null,
    "sessionID": null,
    "message": null
  }
}
```

`state` starts at `launching` and moves to `running` once the worker's own hook events confirm a run started. Exactly one of `--task`/ `--task-file` is required; a task that would push the encoded request over the 64 KiB socket envelope is rejected by the CLI before it ever opens a connection. See [Agent job binding](#agent-job-binding) for what `jobID` actually identifies.

### agent wait

Blocks until the job's own bound run -- never a run that predates the job -- reaches the given condition, or the timeout elapses.

```bash
mytty-ctl agent wait "$job" --until completed
```

```json
{
  "type": "agentWaitResult",
  "job": { "...": "same shape as agent spawn's job" },
  "timedOut": false
}
```

- `running` resolves once the job has bound to a run and that run is running or has moved past running.
- `attention` resolves only for `waiting-input`/`waiting-approval`.
- `completed` resolves for `succeeded`, `failed`, `disconnected`, `launch-failed`, or `lost`.

`--timeout-seconds` defaults to `120`. A provider that never starts (missing executable, a broken hook integration) surfaces as `launch-failed` within 30 seconds of the spawn -- `agent wait` does not sit through the full timeout for that case.

### agent result

Returns the job's latest state together with the pane's current screen content, so a lead can collect what a worker produced after `agent wait --until completed`.

```bash
mytty-ctl agent result "$job"
```

```json
{
  "type": "agentResult",
  "job": { "...": "same shape as agent spawn's job" },
  "content": {
    "paneID": "...",
    "text": "...",
    "cursorRow": 10,
    "cursorColumn": 2
  }
}
```

This reads the pane's current screen, not a provider transcript, so a worker's launch prompt asks it to keep its final summary concise enough to still be legible on screen.

### agent send / agent focus / agent close

Resolve a job ID to its pane and reuse the pane-level `send`/`focus`/ `close-pane` behavior, so a follow-up always reaches the exact worker it was meant for even if other panes were opened or closed in between.

```bash
mytty-ctl agent send "$job" "Also add a regression test." --enter
mytty-ctl agent focus "$job"
mytty-ctl agent close "$job"
```

```json
{ "type": "ok" }
```

`agent close` closes the job's pane and moves a nonterminal job to `lost`. A pane that disappeared on its own (closed by the user, the shell exited, ...) is reported the same way -- `lost`, not `pane-not-found` -- through every `agent` command.

### guide

Prints the pane-team playbook -- environment variables, the split/send/wait/read flow, and per-provider launch commands -- as plain text, and exits 0 without needing `MYTTY_CONTROL_SOCKET` or a running Mytty. This file documents argument syntax and JSON shapes; `mytty-ctl guide` is the primary source for the recipes themselves, so run it directly rather than looking for a copy here. `mytty-ctl --help` (or `-h`, or no arguments) prints the shorter command list above instead. Mytty itself writes this same text to `~/Library/Application Support/mytty/mytty-ctl.md` on every launch, and the "Teach agents about Mytty orchestration" setting for Claude Code / Codex writes a reference to that file (see the [agent providers reference](agent-providers.md)).

```bash
mytty-ctl guide
```

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

`provider` is an `AgentProvider.rawValue` (see [Agent event protocol](agent-event-protocol.md)) and `agentState` an `AgentRunState.rawValue`. Both keys are omitted from the JSON entirely until at least one agent event has been recorded for that pane (verified against a live `mytty-ctl list | jq .` run on a pane with no agent history: no `provider` or `agentState` key appears at all).

### new-tab

Creates a new tab in the active window (or the first window found, if none is active). There is no way to target a specific window; split an existing pane in that window instead.

```bash
mytty-ctl new-tab --cwd /path/to/project
```

```json
{ "type": "pane", "paneID": "..." }
```

`--cwd` defaults to the active window's current working directory when omitted.

### split

Splits an existing pane in the given direction, focusing the target pane first.

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

Sends a single synthesized key event, for interactive prompts that don't respond to plain text (arrow-key menus, `Esc` to cancel, ...).

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

`--modifiers` takes a comma-separated list drawn from `shift`, `control`, `option`, `command` (e.g. `--modifiers shift,command`). An unrecognized `<key>` value fails with the `pane-not-found` error code even when the pane itself exists. `ControlCoordinator` treats "no key mapping" and "no such pane" the same way, so the code name is misleading in this one case. No key event is sent when this happens.

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

`cursorRow` and `cursorColumn` are `null` when the pane has no cursor position to report.

### wait

Blocks until the pane's most relevant agent run satisfies a condition, or until the timeout elapses.

```bash
mytty-ctl wait "$paneA" --until idle
mytty-ctl wait "$paneA" --until attention --timeout-seconds 600
```

```json
{ "type": "waitResult", "state": "idle", "timedOut": false }
```

`--timeout-seconds` defaults to `120`. `state` is the `AgentRunState` observed when the wait resolved (or `null` if no event has ever arrived for that pane); `timedOut` is `true` if the deadline was reached without the condition being satisfied. See [wait semantics](#wait-semantics) below.

### close-pane

Closes a pane immediately, with no confirmation dialog. The caller is assumed to be an automated agent, not a human clicking Close.

```bash
mytty-ctl close-pane "$paneA"
```

```json
{ "type": "ok" }
```

Closing the last pane of the last tab in a window still triggers that window's own close-confirmation dialog, if the user has one configured; this case does not normally arise for panes created to run subagents.

### focus

Brings a pane to the foreground, for handing control back to the user.

```bash
mytty-ctl focus "$paneA"
```

```json
{ "type": "ok" }
```

## Failure responses

A failed request returns `{"type":"failure","code":"..."}` from the server; the CLI surfaces this as a non-zero exit with a stderr message rather than printing the JSON.

| Code | Meaning |
| --- | --- |
| `invalid-request` | The request could not be decoded as JSON, or malformed argument syntax at the CLI layer |
| `not-ready` | The control server has no delegate yet (app still starting) |
| `new-tab-failed` | `new-tab` could not create a tab |
| `split-failed` | `split` could not split the given pane |
| `pane-not-found` | The given `pane-id` does not resolve to a live pane (also returned by `send`, `send-key`, `read`, `wait`, `close-pane`, `focus`); `agent spawn` also returns this if `--anchor` doesn't resolve to a live pane |
| `provider-integration-not-installed` | `agent spawn`: the requested provider's hook integration isn't enabled in Settings |
| `provider-integration-needs-repair` | `agent spawn`: the provider's hook integration is installed but stale/broken |
| `invalid-cwd` | `agent spawn`: `--cwd` doesn't name an existing directory |
| `invalid-label` | `agent spawn`: `--label` contains a control character or exceeds 100 Unicode scalars |
| `invalid-model` | `agent spawn`: `--model` is empty, contains a control character or whitespace, or exceeds 100 Unicode scalars |
| `invalid-task` | `agent spawn`: the resolved task text is empty |
| `inherit-unavailable` | `agent spawn`: `--access inherit` was requested but the anchor pane's foreground process can't be read, or isn't the same provider as `--provider` |
| `spawn-failed` | `agent spawn`: the pane could not be created |
| `job-not-found` | `agent wait`/`agent result`/`agent send`/`agent focus`/`agent close`: the given job ID is unknown -- either it never existed, or it was issued before the last Mytty restart (job IDs are not persisted) |
| `job-lost` | `agent send`/`agent focus`: the job's pane disappeared (see `lost` below); `agent result` and `agent close` do not use this code -- they answer with the job's `lost` state and an empty result, and closing a job whose pane is already gone still exits `0` |

## Wait semantics

`wait` polls at a fixed interval (roughly 300 ms) until the condition is met or the deadline passes.

- `--until idle` resolves once the pane's most recent agent run reaches `idle`, `succeeded`, `failed`, or `disconnected`. A pane that has never received an agent event blocks until timeout; there is no "already idle" default.
- `--until attention` resolves once the run reaches `waiting-input` or `waiting-approval`. Antigravity's installed hooks never emit approval- or input-requested events (see [Agent providers](agent-providers.md)), so `wait --until attention` always times out for panes running that provider; use `--until idle` for it instead. Cursor never emits input-requested either, but it can reach `waiting-approval`: mytty estimates a stuck tool call from a delay between Cursor's `preToolUse` hook and the matching `postToolUse` / `postToolUseFailure`, so `wait --until attention` resolves for a Cursor pane once that estimate fires (roughly 10 seconds after the tool call starts, if nothing resolves it sooner).
- If the target provider's hook integration has not been enabled yet in Settings, no agent events reach Mytty at all and `wait` blocks until timeout regardless of condition. This is the most common cause of an unexpected timeout the first time a provider is used from a script.

`agent wait` polls the same way, against `agent spawn`'s job instead of a pane. Its three conditions (`running`/`attention`/`completed`) are a different set from `wait`'s (`idle`/`attention`) -- see [agent wait](#agent-wait) above.

## Agent job binding

A job created by `agent spawn` identifies one specific worker run, not "whatever the pane is currently doing." Internally, `AgentJobTracker` records the set of run IDs already known for the new pane at the moment it's created (normally empty, since the pane is brand new) and then binds the job to the first later run it observes for that pane/provider whose ID isn't in that set. Once bound, a job never switches to a different run. This is what makes two jobs spawned back to back safe: each is anchored to its own pane and its own baseline, so neither can observe the other's run, and `agent wait --until completed` can never resolve from a run that predates the job.

A job's state comes directly from mapping its bound run's `AgentRunState`, not from `AttentionCenter`'s "most relevant run for this pane" logic that the status bar uses -- the two answer different questions. If no run binds before 30 seconds pass, the job moves to `launch-failed` (covering a missing executable, a TUI that never launched, or hooks that never fired). If the job's pane disappears, a nonterminal job moves to `lost`. Neither transition is reversible.

The job registry lives only in the running app's memory; it is not persisted. A Mytty restart makes previously issued job IDs return `job-not-found` -- the panes/processes those jobs pointed at are unaffected, they're just no longer reachable by that job ID.

## Constraints

- `new-tab` cannot target a specific window; it always lands in the active window, or the first window found if none is active. To open a pane in a specific window, `split` one of that window's existing panes instead.
- `close-pane` never shows a confirmation dialog. The one exception, closing the last pane of the last tab, still triggers the window's own close confirmation; this does not normally apply to panes created for subagent teams.
- Pane IDs are `TerminalSurfaceID` UUID strings, obtained from `list`, a `pane` response, or `$MYTTY_SURFACE_ID`.
- The maximum request size accepted by the control socket matches the agent-event socket's 64 KiB envelope limit; a very large `send` argument should be chunked or piped through the shell instead of passed as one oversized literal. `agent spawn` checks the same limit against the encoded request (task plus the appended worker contract) before opening a connection, so an oversized task fails as a plain CLI error instead of a socket write silently being rejected.
- `agent spawn` never launches a worker in an existing pane -- every spawn creates a new one. This is what keeps job binding correct (see [Agent job binding](#agent-job-binding)); it also means closing jobs you no longer need (`agent close`) matters more than it does for a small number of manually managed panes.
- Job IDs are the `{"rawValue":"..."}` UUID form of `AgentJobID`, read from `job.jobID.rawValue` in any `agent` response. They are not interchangeable with pane IDs.

## See also

- [Orchestrate a team of agents with mytty-ctl](../how-to/orchestrate-agents-with-mytty-ctl.md) walks through staged multi-worker examples built on the `agent` commands.
- [mytty-ctl architecture](../explanation/mytty-ctl-architecture.md) explains why the control socket needs no setup and how job/run binding works underneath `agent wait`.
- [Agent providers](agent-providers.md) covers which providers expose approval/input events, relevant to `wait --until attention`.
- [Agent event protocol](agent-event-protocol.md) documents the `AgentProvider` and `AgentRunState` values surfaced in `list` and `wait`.
- `.claude/skills/mytty-panes/SKILL.md` has task recipes built on these commands.
