# Orchestrate a team of agents with mytty-ctl

`mytty-ctl` is the CLI that ships with Mytty and lets an AI agent open and
drive other panes. Rather than the invisible subagents a `Task`/`Agent`
tool spawns, it runs a small team of subagents in panes that stay visible
and interruptible on screen.

Every pane's shell environment in Mytty automatically has
`MYTTY_CONTROL_SOCKET`, `MYTTY_CTL_BIN`, and `MYTTY_SURFACE_ID` set, so an
agent can call another AI agent right away with something like
`"$MYTTY_CTL_BIN" agent spawn --provider codex --task "..."` -- no other
setup needed.

The full list of `mytty-ctl` commands and their JSON output shapes is in
the [mytty-ctl reference](../reference/mytty-ctl.md).

## Using this

There are two ways to use Mytty orchestration.

### Tell the prompt to run the CLI first

Have the prompt run a command before giving the actual task, like this:

> First run `mytty-ctl guide`, then split a pane and have Claude Code
> review this diff in parallel.

This only needs the CLI installed -- no changes to the CLAUDE.md or
AGENTS.md currently in use.

### Write the usage into CLAUDE.md or AGENTS.md ahead of time

Writing the usage into CLAUDE.md or AGENTS.md means you don't have to
spell out "first run `mytty-ctl guide`" every time -- a prompt like this
is enough:

> Split a pane and have Claude Code review this diff in parallel.

## Settings screen

Everything this feature needs is gathered under Settings > Orchestration.

**Put the CLI on PATH**
"Install CLI" creates a symlink in `~/.local/bin`.

**Teach agents how to use it**
Turning on "Teach agents about Mytty orchestration" writes a short
reference into `~/.claude/skills/mytty-panes/SKILL.md` and
`~/.codex/AGENTS.md`. The actual usage text lives in
`~/Library/Application Support/mytty/mytty-ctl.md`, which Mytty
(re)writes on every launch to match `mytty-ctl guide`'s output --
both references just point at that file's absolute path. So when the
usage changes in a Mytty update, only the bundled guide gets rewritten;
the references themselves never need to change.

"Show what will be written" reveals the exact short reference before
anything is saved; opening it alone doesn't write anything.

The bottom of the same screen lists example prompts to copy from.
