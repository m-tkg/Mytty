---
name: mytty-panes
description: Control multiple Mytty panes via mytty-ctl to run sub-agents (Claude/Codex/Cursor, etc.) in other panes as a team. Use for requests like "split the pane and work in parallel" or "have another AI review this."
---

# mytty-panes: running a sub-agent team across Mytty panes

Run this first, then follow what it prints:

```bash
"$MYTTY_CTL_BIN" guide
```

That command is the single source of truth for the pane-team playbook: the
environment variables, the split/send/wait/read flow, per-provider launch
flags, and the common pitfalls. It ships with the `mytty-ctl` binary, so it
stays in sync with whatever Mytty version is installed — don't duplicate it
here, and don't guess at launch flags from memory.

## This repository

When the controller and the sub-agent are both working in this repo:

- Give each sub-agent its own `git worktree` so builds don't collide; see
  the Commands section of `CLAUDE.md` for `swift build` / `swift test`.
- Point sub-agents at `docs/reference/mytty-ctl.md` and
  `docs/how-to/orchestrate-agents-with-mytty-ctl.md` if they need more detail
  than the guide covers.
- A sub-agent working on Mytty itself should still finish with a passing
  `swift build` and `swift test`, per this repo's workflow rules.
