# Your first agent session

日本語版は [first-agent-session_ja.md](first-agent-session_ja.md) にあります。

This tutorial turns on agent integration for one provider, runs a coding
agent in a pane, and follows a request from that agent into the Attention
Inbox. It assumes you already know your way around tabs and panes; if not,
start with [Getting started with Mytty](getting-started.md) first.

## Turn on a provider

Open **Settings > Agents** and enable one provider. Mytty supports Codex,
Claude Code, OpenCode, Gemini (Antigravity), and Cursor; pick whichever one
you already have installed and logged in. Turning it on installs a hook into
that provider's own configuration file, so the change is confined to that
tool and does not touch anything else you have set up there.

This is worth understanding before you go further: Mytty never reads the
text on screen to figure out what an agent is doing. The hook you just
installed makes the agent itself report structured events, so whatever shows
up later is attributed to the exact pane it came from, not guessed from
scrollback.

## Start the agent and give it something to do

Open a pane and launch the CLI for the provider you enabled, for example
`claude` for Claude Code or `codex` for Codex. Once it is running, ask it to
do something that takes more than a couple of seconds and, ideally, needs an
approval along the way, for example editing a file or running a shell
command. As it works, look at the sidebar row for that pane and the status
bar: both pick up the model in use, remaining context, and an estimated
session cost as soon as the agent reports them. A spinner runs only while the
agent is actually processing a turn, not while it is sitting at a prompt
waiting on you.

## Watch it land in the Attention Inbox

When the agent asks for an approval, or finishes, or fails, that event shows
up in the Attention Inbox. Open it with Command-Shift-A.

![The Attention drawer listing an approval request](../images/attention.png)

Each entry names the pane it came from; the arrow button on the entry jumps
straight to that pane so you can respond. Try switching to a different tab
before the agent asks its next question: the entry is still there waiting
when you check the inbox later, because it stays until you deal with it or
focus the originating pane yourself. If you were already looking at the pane
when the event arrived, it never shows up as unread at all.

If you are elsewhere on the Mac, a macOS notification covers the same ground.
Mytty skips it when the pane in question is already in front of you, so you
will not get a notification for something you just watched happen.

## Keep the Mac awake while it works

Agents tend to run longer than a screensaver timeout allows. **Settings >
General** has a setting to hold sleep off while an agent is actively running,
or for as long as an agent CLI is open in a pane at all, including with the
lid closed via a bundled helper that needs a one-time approval in System
Settings. Turn this on now if you plan to leave an agent running unattended.

## One step further: letting the agent drive Mytty

Everything so far has you watching an agent from outside. `mytty-ctl` is a
CLI that works inside any pane with no setup, and it lets an agent open and
split panes, type into them, read their screens, and wait for another pane's
agent to go idle or need attention. Try it from inside the pane where your
agent is running:

```sh
"$MYTTY_CTL_BIN" split "$MYTTY_SURFACE_ID" right --cwd "$PWD"
```

That opens a new pane to the right of the current one, in the same working
directory, which the agent could then use to run tests or a second agent
alongside the one you are talking to. The point of `mytty-ctl` is that a team
of subagents becomes real panes you can watch and interrupt, rather than
something invisible running behind a single prompt. The full command set,
including waiting on another pane's agent state, is covered in
[Orchestrating agents with mytty-ctl](../how-to/orchestrate-agents-with-mytty-ctl.md).

## Where to go next

- [Orchestrating agents with mytty-ctl](../how-to/orchestrate-agents-with-mytty-ctl.md)
  goes deeper into scripting a pane from another agent.
- [Agent providers](../reference/agent-providers.md) documents exactly what
  each provider reports and how Mytty derives status from it.
