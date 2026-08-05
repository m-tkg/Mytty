# Orchestrate a team of agents with mytty-ctl

`mytty-ctl` is the CLI that ships with Mytty and lets an AI agent open and drive other panes. Rather than the invisible subagents a `Task`/`Agent` tool spawns, it runs a small team of subagents in panes that stay visible and interruptible on screen.

Every pane's shell environment in Mytty automatically has `MYTTY_CONTROL_SOCKET`, `MYTTY_CTL_BIN`, and `MYTTY_SURFACE_ID` set, so an agent can call another AI agent right away with something like `"$MYTTY_CTL_BIN" agent spawn --provider codex --task "..."` -- no other setup needed.

The full list of `mytty-ctl` commands and their JSON output shapes is in the [mytty-ctl reference](../reference/mytty-ctl.md).

## Using this

There are two ways to get an agent to read the guide.

### Just mention Mytty

With "Teach agents about Mytty orchestration" on (Settings > Orchestration), mentioning Mytty anywhere in the request is enough -- the reference it writes (`~/.claude/skills/mytty-panes/SKILL.md` for Claude Code, a block in `~/.codex/AGENTS.md` for Codex) triggers on that alone and points the agent at `mytty-ctl guide`:

> With Mytty, split a pane and have Claude Code review this diff in parallel.

### Skip mentioning it too: write the usage into CLAUDE.md or AGENTS.md

Writing the usage into this repo's own CLAUDE.md or AGENTS.md means a request doesn't even need to say "Mytty" -- a prompt like this is enough:

> Split a pane and have Claude Code review this diff in parallel.

## A staged example: two workers, then collect

This spawns two read-only investigation workers in parallel, waits for both, and collects what they found, using the `agent` commands directly:

```bash
job_a=$(mytty-ctl agent spawn --provider claude --worktree investigate-a \
  --task "Investigate why login times out under load." \
  --label investigate-a | jq -r '.job.jobID.rawValue')
job_b=$(mytty-ctl agent spawn --provider claude --worktree investigate-b \
  --task "Investigate whether the timeout is client- or server-side." \
  --label investigate-b | jq -r '.job.jobID.rawValue')
```

Both workers are `claude`, the same provider as the lead calling this, so omitting `--access` inherits the lead's own permission mode instead of defaulting to a fixed flag set. `--worktree` gives each worker its own git worktree so the two don't fight over the same files.

```bash
mytty-ctl agent wait "$job_a" --until completed
mytty-ctl agent wait "$job_b" --until completed
findings_a=$(mytty-ctl agent result "$job_a" | jq -r '.content.text')
findings_b=$(mytty-ctl agent result "$job_b" | jq -r '.content.text')
```

Two sequential waits are fine for two workers. Watching more than a couple at once, poll `events` in a loop instead of blocking on one `wait`/`agent wait` per pane -- one long-poll call picks up whichever worker's state changes next, on any pane:

```bash
cursor=$(mytty-ctl events | jq -r '.latestSequence')
while true; do
  response=$(mytty-ctl events --after "$cursor" --timeout 60)
  cursor=$(echo "$response" | jq -r '.latestSequence')
  echo "$response" | jq -c '.records[]'   # act on paneID/kind for whichever job changed
done
```

See the [mytty-ctl reference](../reference/mytty-ctl.md) for the full command list, JSON shapes, and failure codes -- this page stays a quick tour, not the reference.

## Hooks are optional

A worker's run state (running, idle, succeeded, failed, disconnected) is observable even for a provider whose hook integration was never installed in Settings -- Mytty estimates it natively from the pane's foreground process. Installing the provider's hooks raises the fidelity of that state (real lifecycle events instead of an estimate) and is required for `wait --until attention`/`agent wait --until attention`: native estimation deliberately never reports an approval or input request, so an attention wait against a provider with no hooks installed fails fast instead of blocking.

## Settings screen

Everything this feature needs is gathered under Settings > Orchestration.

![Settings > Orchestration, with the Install CLI button and the toggle that teaches agents about Mytty orchestration](../images/orchestration-settings.png)

**Put the CLI on PATH** "Install CLI" creates a symlink in `~/.local/bin`.

**Teach agents how to use it** Turning on "Teach agents about Mytty orchestration" writes a short reference into `~/.claude/skills/mytty-panes/SKILL.md` and `~/.codex/AGENTS.md`. The actual usage text lives in `~/Library/Application Support/mytty/mytty-ctl.md`, which Mytty (re)writes on every launch to match `mytty-ctl guide`'s output -- both references just point at that file's absolute path. So when the usage changes in a Mytty update, only the bundled guide gets rewritten; the references themselves never need to change.

"Show what will be written" reveals the exact short reference before anything is saved; opening it alone doesn't write anything.

The bottom of the same screen lists example prompts to copy from.
