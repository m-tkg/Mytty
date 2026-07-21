# Install and verify agent integrations

This is how to turn on hook-based integration for a coding agent provider and
confirm it actually works, rather than assuming a toggle in Settings is
enough.

## Enable a provider

Open **Settings > Agent Integrations** and turn on a provider. Mytty writes
hook configuration into that provider's own config file only after this
toggle is switched on; nothing is installed ahead of time. Supported
providers are Codex, Claude Code, OpenCode, Gemini (Antigravity), and Cursor.

The Settings screen derives each provider's status from its actual
configuration file rather than from whether you clicked the toggle. If the
installed hooks were edited or partially removed outside Mytty, the provider
shows **Needs repair** instead of quietly appearing installed. Toggling the
provider off and back on rewrites the hook entries without disturbing
unrelated configuration in that file: Mytty only touches the handlers that
invoke its own `mytty-agent-hook` helper.

## Restart the provider

A running provider process does not pick up a hook installed after it
started, so an existing session keeps working exactly as it did before.

For Codex, restart the CLI and also review the new hooks, since Codex
requires explicit trust for command hooks:

1. Exit the running Codex CLI and start a new process.
2. Run `/hooks` in the new process.
3. Select an event that has an installed mytty hook and press Return.
4. Select the command ending in `mytty-agent-hook codex`.
5. If its `Trust` field needs review, press Space or Return to approve it.
6. Repeat until every mytty entry shows `Trust: Trusted`. In the event list,
   `Active` should then equal `Installed`.

Claude Code, OpenCode, Antigravity, and Cursor just need a restart so they
reload their user settings, hooks, or plugin, with no separate trust step.

## Verify it end to end

Start a fresh session with the provider and work through this checklist:

1. Submit a prompt. The tab should switch to a running agent state.
2. For Codex, Claude Code, or OpenCode, trigger a permission or input
   request. The tab badge and the Attention drawer should show one
   actionable item.
3. Keep that tab visible on screen and trigger another request. No macOS
   notification should fire, since the pane is already in front of you.
4. Switch to another tab and trigger a request again. This time a macOS
   notification should arrive, assuming Mytty has notification permission.
5. Use **Focus Terminal** and **Acknowledge** from the Attention drawer entry
   to confirm both actions land on the right pane.
6. Disable the provider in Settings and confirm any unrelated hooks already
   in that config file keep running.

Antigravity's installed hooks only report lifecycle and result status;
they never create approval or input requests, so step 2 does not apply
to it. Cursor's hooks don't create one directly either, but mytty
estimates a shell approval request from a delay between its
`beforeShellExecution` and `afterShellExecution` hooks (see
[Agent providers](../reference/agent-providers.md)) — to see it in step
2, run a command Cursor doesn't auto-approve and wait roughly 10 seconds
without answering the prompt in Cursor's own UI.

## Provider hook references

- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [OpenCode plugins](https://opencode.ai/docs/plugins/)
- [Antigravity hooks](https://www.antigravity.google/docs/hooks)
- [Antigravity plugins](https://www.antigravity.google/docs/plugins)
- [Cursor hooks](https://cursor.com/docs/hooks)

For what each provider's events map to internally, see
[Agent providers](../reference/agent-providers.md).
