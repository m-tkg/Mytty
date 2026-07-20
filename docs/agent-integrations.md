# Agent Integrations

Status: Implemented for development builds. Release app packaging is pending.

mytty installs integrations only after the user enables a provider in
**Settings > Agent Integrations**. The installer derives status from the actual
provider configuration, so a partial or edited installation appears as
**Needs repair** instead of being treated as installed.

## Owned files and handlers

The shared helper is copied to:

```text
~/Library/Application Support/mytty/bin/mytty-agent-hook
```

Provider configuration is updated as follows:

| Provider | Location | Installation |
| --- | --- | --- |
| Codex | `~/.codex/hooks.json` | Adds command handlers for prompt, permission, post-tool, and stop events |
| Claude Code | `~/.claude/settings.json` | Adds command handlers for prompt, permission, post-tool, notification, stop, and failure events |
| OpenCode | `~/.config/opencode/plugins/mytty.js` | Creates one mytty-owned global plugin |
| Gemini (Antigravity) | `~/.gemini/config/plugins/mytty/` | Creates one mytty-owned plugin with invocation and stop hooks |
| Cursor | `~/.cursor/hooks.json` | Adds command handlers for prompt, post-tool, and stop events |

Codex, Claude Code, and Cursor JSON is parsed structurally and written
atomically. Unrelated top-level values, matcher groups, and handlers remain in
place. Removal filters only handlers that invoke mytty's stable helper path
with the matching provider argument. OpenCode removal deletes only `mytty.js`.
Antigravity removal deletes only mytty's plugin directory.

Malformed JSON is never replaced. Settings reports the provider configuration
as invalid and leaves the file unchanged.

## Lifecycle mapping

One agent run represents one prompt or turn, not an entire long-lived CLI
session. This allows a new prompt to start after the preceding turn completed.

| mytty event | Codex | Claude Code | OpenCode | Antigravity | Cursor |
| --- | --- | --- | --- | --- | --- |
| `started` | `UserPromptSubmit` | `UserPromptSubmit` | user `message.updated` | not exposed | `beforeSubmitPrompt` |
| `approval-requested` | `PermissionRequest` | `PermissionRequest` or permission notification | `permission.asked` / `permission.updated` | not exposed | not exposed |
| `input-requested` | input-oriented permission tool | input notification or `AskUserQuestion` | `question.asked` | not exposed | not exposed |
| `running` | `PostToolUse` | `PostToolBatch` | `permission.replied` | `PreInvocation` / `PostInvocation` | `postToolUse` / `postToolUseFailure` |
| `succeeded` | `Stop` | `Stop` | `session.idle` | idle `Stop` | `stop` with `completed` |
| `failed` | not exposed by the installed hooks | `StopFailure` | `session.error` | error `Stop` | `stop` with `error` |
| `disconnected` | not exposed | not exposed | not exposed | not exposed | `stop` with `aborted` |

Codex `turn_id`, Claude Code `prompt_id`, the active OpenCode user message ID,
Antigravity `conversationId`, and Cursor `generation_id` are converted to
stable mytty run identifiers. Hook payloads are never stored or parsed from
human-readable terminal output.

The status bar keeps the separate provider session identifier. For Codex,
mytty binds the foreground PID to the transcript that process has open and
reads its `session_id`, with the hook event value as a fallback. Claude Code
uses hook `session_id`, OpenCode uses `sessionID`, Antigravity uses
`conversationId`, and Cursor uses `conversation_id` or the Cursor CLI
`session_id` alias.

Claude Code fires no hook when the user interrupts a prompt with ESC, so a run
would stay `running` forever. The poller derives that case from the same
transcript it already reads: an entry carrying `interruptedMessageId` as the
newest `promptId`'s last row synthesizes an `idle` event for that run. The
event's run is keyed by `promptId`, so it lands on the run the hooks created;
its identity also includes `interruptedMessageId`, so re-reading the same
interrupt is a no-op while a second interrupt of the same prompt still ends it.

The installed Antigravity and Cursor hook sets currently provide lifecycle and
result status only. They do not create Attention approval or input requests.

The status bar also shows the active model name and, where available, a
remaining-context meter, sourced from local transcripts rather than hook
payloads. For Codex, `CodexSessionInspector` tails the transcript bound to the
foreground PID and reads `turn_context.model` and the latest
`token_count.info` usage. For Claude Code, `ClaudeCodeSessionInspector` finds
`~/.claude/projects/<session-id>.jsonl` (searched across project directories)
or, without a hook session ID, the most recently modified transcript under
`~/.claude/projects/<slug>/`, where `<slug>` replaces every non-alphanumeric
character in the working directory path with `-`; it reads the last
`assistant` line's `message.model` and sums
`input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
against a 1,000,000-token window for `[1m]` models or 200,000 otherwise. For
OpenCode, `OpenCodeSessionInspector` queries the `message` table in
`opencode.db` for the newest assistant row's `modelID` for the hook session
ID. For Cursor, `CursorSessionInspector` locates the chat conversation
directory under `~/.cursor/chats/<workspace-hash>/<session-id>/` (by hook
session ID, or by the newest `meta.json` whose `cwd` matches the pane's
working directory) and scans `store.db`'s `blobs` table, newest row first,
for a `providerOptions.cursor.modelName` field (message blobs sometimes carry
a binary prefix, so this is a text scan rather than a JSON decode). For
Antigravity, `AntigravitySessionInspector` reads the globally selected
`model` from `~/.gemini/antigravity-cli/settings.json`; this is not scoped to
a session, so it requires a hook session ID before showing anything, to avoid
attributing the global setting to an unrelated pane. OpenCode, Cursor, and
Antigravity do not expose a context window size locally, so only the model
name is shown for these three and the remaining-context meter stays hidden;
Antigravity's conversation database remains unusable for this purpose since
it is protobuf-encoded with no stable schema to parse. To keep the
0.5-second foreground poll cheap, Claude Code transcript reads are skipped
unless the tracked (mtime, size) fingerprint changed, and the OpenCode,
Cursor, and Antigravity lookups share a per-pane cache that is throttled to
once every 5 seconds and invalidated immediately if the hook session ID
changes.

When **On Launch** is set to **Restore last session**, mytty also restores an
agent that was running in a terminal pane when the last session snapshot was
saved. The snapshot records the provider-specific session identifier and the
launcher kind, then submits one of the following commands as the restored
shell's initial input:

| Agent | Resume command |
| --- | --- |
| Codex | `codex resume -- <session-id>` |
| Claude Code | `claude --resume=<session-id>` |
| OpenCode | `opencode --session=<session-id>` |
| Gemini CLI | `gemini --resume=<session-id>` |
| Antigravity CLI | `agy --conversation=<session-id>` |
| Cursor | `cursor-agent --resume=<session-id>` |

Resume metadata is regenerated only from an agent process that is still
running and has a known session identifier. Old metadata is consumed once and
is not retained after the agent exits. Session identifiers are length-checked,
rejected when they contain control characters, and POSIX-quoted before they
are submitted to the restored shell.

## Activation and verification

After installing an integration, start a new provider session inside a mytty
terminal. Existing provider processes do not inherit a newly installed hook or
the surface-scoped `MYTTY_*` environment.

Codex requires changed command hooks to be reviewed before they run:

1. Exit the running Codex CLI and start a new process. An existing process does
   not reload hooks installed after it started.
2. Run `/hooks` in the new Codex process.
3. Select an event with an installed mytty hook and press Return.
4. Select the command ending in `mytty-agent-hook codex`.
5. If its `Trust` field needs review, press Space or Return and approve it.
6. Repeat for the mytty entries until each shows `Trust: Trusted`. In the event
   list, `Active` should then equal `Installed`.

Claude Code, OpenCode, Antigravity, and Cursor should also be restarted so they
reload their user settings, hooks, or plugin.

Verify each state from a new session:

1. Submit a prompt. The tab should show a running agent state.
2. For Codex, Claude Code, or OpenCode, trigger a permission or input request.
   The tab badge and Attention drawer should show one actionable item.
3. Keep that tab visible. No macOS notification should be sent.
4. Switch to another tab and trigger another request. A macOS notification
   should be sent when the app has notification permission.
5. Use **Focus Terminal** and **Acknowledge** in the Attention drawer.
6. Disable the provider in Settings and confirm its unrelated hooks still run.

Current provider hook references:

- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [OpenCode plugins](https://opencode.ai/docs/plugins/)
- [Antigravity hooks](https://www.antigravity.google/docs/hooks)
- [Antigravity plugins](https://www.antigravity.google/docs/plugins)
- [Cursor hooks](https://cursor.com/docs/hooks)
