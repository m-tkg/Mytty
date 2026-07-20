---
name: mytty-panes
description: Control multiple Mytty panes via mytty-ctl to run sub-agents (Claude/Codex/Cursor, etc.) in other panes as a team. Use for requests like "split the pane and work in parallel" or "have another AI review this."
---

# mytty-panes: running a sub-agent team across Mytty panes

This skill outlines how the currently running AI (in this pane) acts as the
"controller": it opens other panes with `mytty-ctl`, launches agents there,
waits for them to finish, and collects the results. See
`docs/reference/mytty-ctl.md` for the full protocol and architecture.

## Prerequisites

`mytty-ctl` works from this pane without extra setup. These environment
variables are already set:

```bash
echo "$MYTTY_CTL_BIN"       # absolute path to the mytty-ctl binary
echo "$MYTTY_SURFACE_ID"    # this pane's own pane ID
```

The examples below assume `mytty-ctl` is on `PATH`, but using
`"$MYTTY_CTL_BIN"` directly is more reliable.

## Basic steps

1. **Claim a pane**: `mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd <working-dir>`.
   To keep sub-agents from fighting over the same files, pass a separate
   directory per `git worktree` where possible. Note the `paneID` from the
   JSON response.
2. **Launch the agent**: `mytty-ctl send <paneID> "claude" --enter`
   (or `codex` / `cursor-agent`, etc.).
3. **Send the instruction**: `mytty-ctl send <paneID> "<prompt>" --enter`.
4. **Wait for completion**: `mytty-ctl wait <paneID> --until idle`. To run
   several panes in parallel, fire this `wait` for each pane with the Bash
   tool's `run_in_background: true`, and move to the next step as each
   completion notification arrives.
5. **Collect the results**: `mytty-ctl read <paneID>` retrieves the screen
   text; summarize and consolidate it for the user.
6. **Clean up**: once done, `mytty-ctl close-pane <paneID>`. Leave the pane
   open if the conversation needs to continue.

## Recipes

### Horizontal split: parallel execution with a single provider

Split independent tasks that share the same judgment criteria across
multiple instances of the same provider.

```bash
pane_a=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd worktrees/a | jq -r .paneID)
pane_b=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd worktrees/b | jq -r .paneID)
mytty-ctl send "$pane_a" "claude" --enter
mytty-ctl send "$pane_a" "<task A instructions>" --enter
mytty-ctl send "$pane_b" "claude" --enter
mytty-ctl send "$pane_b" "<task B instructions>" --enter
# Wait on `mytty-ctl wait <pane> --until idle` for each pane in parallel,
# and collect with `mytty-ctl read <pane>` as each one finishes
```

### Role split (survey by Claude, implementation by Codex, controller is the current AI)

For phases that run sequentially, where each phase needs a different
strength. The controller's job is to summarize the previous phase's output
and fold it into the next prompt.

```bash
pane=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd . | jq -r .paneID)
mytty-ctl send "$pane" "claude" --enter
mytty-ctl send "$pane" "<survey task>" --enter
mytty-ctl wait "$pane" --until idle
survey=$(mytty-ctl read "$pane" | jq -r .content.text)
mytty-ctl close-pane "$pane"

pane=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd . | jq -r .paneID)
mytty-ctl send "$pane" "codex" --enter
mytty-ctl send "$pane" "Implement this based on the survey results: $survey" --enter
mytty-ctl wait "$pane" --until idle
mytty-ctl read "$pane"
```

### Implementation + independent review (second opinion)

Offsets self-review bias with a different provider's perspective.

```bash
diff=$(mytty-ctl send "$impl_pane" "git diff" --enter; mytty-ctl read "$impl_pane" | jq -r .content.text)
review_pane=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd . | jq -r .paneID)
mytty-ctl send "$review_pane" "claude" --enter
mytty-ctl send "$review_pane" "Review this diff: $diff" --enter
mytty-ctl wait "$review_pane" --until idle
mytty-ctl read "$review_pane"
# If there's feedback: mytty-ctl send "$impl_pane" "Fix <feedback>" --enter
```

### Escalating on approval prompts

Detect when an agent is blocked waiting for approval on a destructive
operation, and check with the user. Cursor and Antigravity don't emit
`attention` events, so for them only `idle` wait is supported.

```bash
mytty-ctl wait "$pane" --until attention --timeout-seconds 600
mytty-ctl read "$pane"   # check what's being asked before relaying it to the user
```

## Notes

- `wait` watches the agent's hook events (`AgentRunState`). If the target
  provider's integration isn't enabled in Settings, no events arrive and the
  wait blocks until it times out. Check this before using a provider for the
  first time.
- `close-pane` closes immediately without confirmation. For panes you want
  to show a human, move focus with `mytty-ctl focus <paneID>` instead of
  closing them.
- Only let sub-agents spawn further sub-agents (grandchild agents) when
  that's intentional — unbounded nesting becomes unmanageable.
