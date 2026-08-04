# Agent providers reference

Mytty supports five agent providers, identified in code by `AgentProvider` (`Sources/MyTTYCore/AgentEvent.swift`): `codex`, `claude-code`, `opencode`, `antigravity`, `cursor`. This page lists, per provider, the configuration file Mytty installs hooks into, which Mytty event kinds each provider's hooks can emit, and how session resume works. For the wire format of the events themselves, see [Agent event protocol](agent-event-protocol.md).

The Antigravity provider covers two distinct binaries under one event category. `AgentProvider.antigravity` is a single protocol-level category for both the Google Antigravity IDE's agent and the standalone Gemini CLI; their hook events look identical to Mytty. Session resume is where they diverge. Mytty inspects the foreground process's executable basename and picks `gemini --resume=<id>` when it looks like the Gemini CLI (basename `gemini` or `gemini-cli`, or a path containing `/gemini-cli/`), and `agy --conversation=<id>` otherwise. See `AgentResumeLaunchPlan.isGeminiCLI` in `Sources/MyTTYApp/AgentSessionRestoration.swift`. Some in-app labels and older docs shorten this to "Gemini (Antigravity)"; that label names the provider, not a resume command.

## Foreground provider detection and the `MYTTY_AGENT` hint

The status bar identifies the agent running in a pane by inspecting the foreground process's executable path and the first argv entries (`TerminalAgentProcessDetector.provider(executablePath:arguments:)` in `Sources/MyTTYApp/TerminalAgentProcessDetector.swift`). That works for agents launched directly, but gives no signal when the agent runs behind a wrapper whose binary name says nothing about it — `ssh` into a remote box, `docker exec` into a container, or a launcher script.

For those cases, export `MYTTY_AGENT=<provider>` in the wrapper's environment before launching it. When path/argv detection identifies no provider, Mytty falls back to reading this variable from the wrapper process's exec-time environment. The value must be one of the `AgentProvider` identifiers — `codex`, `claude-code`, `opencode`, `antigravity`, `cursor` — compared after trimming whitespace and lowercasing; anything else is ignored. A hint never overrides real detection, and it only affects provider identification (the status bar label and provider-scoped lookups). Hook events still have to reach Mytty's event socket, which a remote host or container cannot do, so panes detected via the hint typically show the provider without run states.

```sh
MYTTY_AGENT=claude-code ssh devbox
```

## Owned files and handlers

The shared hook helper binary lives at `~/Library/Application Support/mytty/bin/mytty-agent-hook`. Enabling a provider in **Settings > Agents** writes to:

| Provider | Configuration file | What gets written |
| --- | --- | --- |
| Codex | `~/.codex/hooks.json` | Command handlers for prompt, permission, post-tool, and stop events |
| Claude Code | `~/.claude/settings.json` | Command handlers for prompt, permission, post-tool, notification, stop, and failure events |
| OpenCode | `~/.config/opencode/plugins/mytty.js` | One mytty-owned global plugin file |
| Antigravity | `~/.gemini/config/plugins/mytty/` | One mytty-owned plugin directory with invocation and stop hooks |
| Cursor | `~/.cursor/hooks.json` | Command handlers for prompt, pre-tool, post-tool, and stop events |

Codex, Claude Code, and Cursor configuration is JSON, parsed structurally and rewritten atomically; unrelated top-level values, matcher groups, and handlers are left untouched. Removal deletes only the handlers whose command invokes mytty's own helper path with the matching provider argument. Disabling OpenCode deletes only `mytty.js`; disabling Antigravity deletes only mytty's plugin directory. Malformed JSON is never overwritten. Settings reports the provider's configuration as invalid and leaves the file as-is.

Each provider's Settings row derives **Installed** / **Needs Repair** / **Not Installed** from the actual file contents, not from whether the toggle was clicked. A hand-edited or partially removed installation shows **Needs Repair**.

**Teach agents about Mytty orchestration** (Settings > Orchestration, on by default) writes a short reference into a second, independent artifact for the two providers where a global pointer location is known:

| Provider | File | What gets written |
| --- | --- | --- |
| Claude Code | `~/.claude/skills/mytty-panes/SKILL.md` | A user skill, entirely owned by Mytty; body is just a few lines of reference |
| Codex | `~/.codex/AGENTS.md` | A `<!-- mytty:pane-team:begin -->` / `:end` managed block; everything outside it is untouched; body is just a few lines of reference |

Neither embeds the actual usage text (the environment variables, the split/send/wait/read flow, per-provider launch flags). Instead, Mytty writes that to `~/Library/Application Support/mytty/mytty-ctl.md` on every launch (`ControlCommandLineParser.paneTeamGuide`, the same English-only text `mytty-ctl guide` prints). Both SKILL.md and the AGENTS.md block just point at that file's absolute path rather than duplicating its contents, so when a Mytty update changes the usage text only `mytty-ctl.md` needs rewriting -- the two reference files stay accurate without their own repair beyond keeping that path current. Cursor, OpenCode, and Antigravity are not covered: no documented global-instruction location has been confirmed for them.

The reference prose itself follows Settings > General's language setting (English or Japanese); `mytty-ctl.md`'s body (`paneTeamGuide`) is English only and unaffected by that setting. Resolving `AppLanguage.systemDefault` stays the app layer's job -- MyTTYCore only ever receives an already-resolved language. Switching the setting rewrites any already-installed pointer to match on the next application preference change (`AgentIntegrationSettingsModel.repairInstalledIntegrations(language:)`). The managed block's `<!-- mytty:pane-team:begin -->` / `:end` markers and the skill's `name: mytty-panes` stay the same regardless of language.

## Lifecycle mapping

One Mytty agent run represents one prompt or turn, not an entire long-lived CLI session, so a new prompt starts a new run once the previous one completes.

| Mytty event | Codex | Claude Code | OpenCode | Antigravity | Cursor |
| --- | --- | --- | --- | --- | --- |
| `started` | `UserPromptSubmit` | `UserPromptSubmit` | user `message.updated` | not exposed | `beforeSubmitPrompt` |
| `approval-requested` | `PermissionRequest` | `PermissionRequest` or permission notification | `permission.asked` / `permission.updated` | not exposed | estimated (see below) |
| `input-requested` | input-oriented permission tool | input notification or `AskUserQuestion` | `question.asked` | not exposed | not exposed |
| `running` | `PostToolUse` | `PostToolBatch` | `permission.replied` | `PreInvocation` / `PostInvocation` | `preToolUse` / `postToolUse` / `postToolUseFailure` |
| `succeeded` | `Stop` | `Stop` | `session.idle` | idle `Stop` | `stop` with `completed`, or no `status` field at all |
| `failed` | not exposed by the installed hooks | `StopFailure` | `session.error` | error `Stop` | `stop` with `error` |
| `disconnected` | not exposed | not exposed | not exposed | not exposed | `stop` with `aborted` |

Antigravity's installed hooks provide lifecycle and result status only; they never produce `approval-requested` or `input-requested`, which is why `mytty-ctl wait --until attention` never resolves for panes running that provider (see [mytty-ctl reference](mytty-ctl.md)).

Cursor has no hook of its own for a permission prompt either, but Mytty estimates one from `preToolUse`, which fires before every tool call -- not just shell commands, but file edits and deletes too, which also prompt for approval. `preToolUse` starts a 10-second timer keyed by that call's `tool_use_id`; if the matching `postToolUse`, `postToolUseFailure` (same `tool_use_id`), or the run's `stop` arrives first, the timer is cancelled. Tool calls can run concurrently -- Cursor has been observed firing `preToolUse` for two different tools back to back before either one's `postToolUse` arrives -- so pending timers are tracked per `tool_use_id`, not per run, or a still-pending call could be forgotten as soon as any other call in the same run resolves. If nothing arrives in time, Mytty synthesizes an `approval-requested` event itself -- `CursorApprovalPendingTracker` holds the pending state, `CursorApprovalCoordinator` (`Sources/MyTTYApp/CursorApprovalCoordinator.swift`) owns the timer, and `AgentHookEventAdapter.pendingApprovalEvent` builds the event. Once the matching `postToolUse` or `postToolUseFailure` does arrive, the run transitions back to `running` the same way a real approval resolves, so no separate resolution step is needed. Auto-approved calls that finish inside the 10-second window never trigger this at all; one that runs long but was in fact auto-approved briefly shows as `approval-requested` in Attention and then resolves itself once its `postToolUse` lands.

Mytty no longer installs handlers on Cursor's `beforeShellExecution` / `afterShellExecution` hooks, and no longer uses them to detect a pending approval: they only bracket shell commands, so a tool call stuck on an approval prompt for a non-shell tool (a file delete, observed in practice) never produced either hook, and the delay-based estimate built on them missed it. The mapping for those two hooks is still recognized for anyone who installed them by hand, but installing or repairing the Cursor integration in Settings now writes `preToolUse` instead.

Provider-native identifiers are converted to Mytty run identifiers as follows: Codex `turn_id`, Claude Code `prompt_id`, the active OpenCode user message ID, Antigravity `conversationId`, Cursor `generation_id`. Hook payloads themselves are never stored or parsed from human-readable terminal output.

## Status bar session identifier

The status bar's session identifier comes from a separate, provider-specific source per provider:

| Provider | Source |
| --- | --- |
| Codex | The transcript bound to the foreground PID; falls back to the hook event's value |
| Claude Code | Hook `session_id` |
| OpenCode | Hook `sessionID` |
| Antigravity | Hook `conversationId` |
| Cursor | Hook `conversation_id`, or the Cursor CLI `session_id` alias |

Claude Code fires no hook when the user interrupts a prompt with Esc, so without special handling a run would stay `running` forever. The poller recovers this from the transcript it already reads: an entry carrying `interruptedMessageId` as the newest `promptId`'s last row synthesizes an `idle` event, keyed by that `promptId` so it lands on the run the hooks created. The event's identity also includes `interruptedMessageId`, so re-reading the same interrupt is a no-op, while a second interrupt of the same prompt still ends the run.

## Model name and context meter sources

The status bar's model name and, where available, remaining-context meter come from local transcripts, not hook payloads, via each provider's `*SessionInspector` (`Sources/MyTTYCore`):

| Provider | Inspector | Source | Context window |
| --- | --- | --- | --- |
| Codex | `CodexSessionInspector` | Transcript bound to the foreground PID: `turn_context.model` and the latest `token_count.info` | Reported by the transcript |
| Claude Code | `ClaudeCodeSessionInspector` | `~/.claude/projects/<session-id>.jsonl` (searched across project dirs), or without a hook session ID, the most recently modified transcript under `~/.claude/projects/<slug>/`; last `assistant` line's `message.model`, tokens summed as `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` | 1,000,000 for `[1m]` models, 200,000 otherwise |
| OpenCode | `OpenCodeSessionInspector` | `message` table in `opencode.db`, newest assistant row's `modelID` for the hook session ID | not exposed locally |
| Cursor | `CursorSessionInspector` | Chat directory under `~/.cursor/chats/<workspace-hash>/<session-id>/` (by hook session ID, or newest `meta.json` whose `cwd` matches the pane); `store.db`'s `blobs` table, newest row first, text-scanned for `providerOptions.cursor.modelName` | Newest "root" blob's protobuf record: top-level field 5 holds used/total token counts; `nil` on older Cursor CLI versions that never write that blob |
| Antigravity | `AntigravitySessionInspector` | Globally selected `model` in `~/.gemini/antigravity-cli/settings.json`; requires a hook session ID first, since the setting isn't scoped to a session | not exposed locally (conversation DB is protobuf-encoded with no stable schema) |

The context meter turns red once the remaining context falls below a threshold, so a pane that is about to run out stands out without a notification. **Settings > Agents > Warn on low context** turns the warning off or moves the threshold (default 30%); the comparison uses the rounded remaining percentage, whichever side the meter displays.

The context meter and the usage-limit meters next to it graph what is left by default. **Settings > Agents > Meter shows** switches both to the amount used instead, which only flips the presentation: everything Mytty reads is still a remaining amount, so the low-context warning keeps comparing the remaining percentage against the same threshold.

`<slug>` for Claude Code replaces every non-alphanumeric character in the working directory path with `-`. To keep the 0.5-second foreground poll cheap, Claude Code transcript reads are skipped unless the tracked `(mtime, size)` fingerprint changed; the OpenCode, Cursor, and Antigravity lookups share a per-pane cache throttled to once every 5 seconds, invalidated immediately if the hook session ID changes.

Cursor's status-bar dollar cost comes from `GET https://cursor.com/api/usage-summary`'s `individualUsage.onDemand`, but that field only carries a cost for accounts with usage-based pricing enabled — on plan/free accounts it is disabled and Mytty falls back to `POST https://cursor.com/api/dashboard/get-aggregated-usage-events` (same cookie, plus an `Origin: https://cursor.com` header and the usage-summary response's billing-cycle dates as the request window), reading `totalCostCents` as the session cost.

## Session restoration (resume commands)

When **On Launch** is set to **Restore last session**, Mytty restores an agent that was running in a pane when the session snapshot was saved, by submitting one of these commands as the restored shell's initial input:

| Agent | Resume command |
| --- | --- |
| Codex | `codex resume -- <session-id>` |
| Claude Code | `claude --resume=<session-id>` |
| OpenCode | `opencode --session=<session-id>` |
| Gemini CLI | `gemini --resume=<session-id>` |
| Antigravity CLI | `agy --conversation=<session-id>` |
| Cursor | `cursor-agent --resume=<session-id>` |

Gemini CLI and Antigravity CLI share `AgentProvider.antigravity`; which resume command is chosen depends on the foreground process's executable basename at snapshot time, not on any separate provider value (see `AgentResumeLaunchPlan.kind` in `Sources/MyTTYApp/AgentSessionRestoration.swift`).

Resume metadata regenerates only from an agent process that is still running and has a known session identifier, and is consumed once. It does not persist after the agent exits. Session identifiers are length-checked, rejected if they contain control characters, and POSIX-quoted before being submitted to the restored shell.

## References

- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [OpenCode plugins](https://opencode.ai/docs/plugins/)
- [Antigravity hooks](https://www.antigravity.google/docs/hooks)
- [Antigravity plugins](https://www.antigravity.google/docs/plugins)
- [Cursor hooks](https://cursor.com/docs/hooks)
