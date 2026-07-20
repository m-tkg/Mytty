[日本語](README_ja.md)

# Mytty

**New here? Start with the [usage guide](docs/usage.md) — screenshots and the
things you will do first.**

## Overview

Mytty is an Apple Silicon, macOS-native terminal for an AI-assisted workflow.
It embeds libghostty for Metal-accelerated terminal rendering and uses AppKit,
SwiftUI, and WebKit for its surrounding interface. The terminal remains the
primary surface: Mytty adds tabs, panes, agent status, an Attention Inbox, and
small workflow tools without introducing a workspace abstraction.

Mytty supports Codex, Claude Code, OpenCode, Gemini (Antigravity), and Cursor.
Provider integrations deliver structured events through a pane-scoped Unix
socket. This lets Mytty associate an agent request with the correct pane
without parsing human-readable terminal output.

The current release requires macOS 15 or later and Apple Silicon.

## Features

- **Ghostty terminal engine:** libghostty rendering, native IME, themes,
  configurable fonts, cursor style, opacity, and light/dark appearance.
- **Simple tabs and panes:** four-way splits, drag-to-reorder tabs, pane zoom,
  equalized layouts, movable tab panels, and an all-panes switcher.
- **Command palette:** Command-Shift-P opens a searchable list of every menu
  command; type to filter (fuzzy matching included) and press Return to run.
- **Agent-aware status:** active agent, session cost, quota meters when
  available, processing state, GitHub repository and branch, working folder,
  sleep prevention, and scheduled input.
- **Attention Inbox:** persistent approval, input, success, and failure events
  that navigate directly to the originating pane.
- **AI control (`mytty-ctl`):** a local CLI, usable from inside any pane with
  no setup, that lets an AI agent open/split panes, type into them, read their
  screens, and wait for another pane's agent to go idle or need attention —
  so an AI can run a team of subagents as real, visible panes.
- **Session restoration:** windows, tabs, terminal/browser panes, split ratios,
  working directories, and resumable agent sessions.
- **Local autocomplete:** inline shell-history suggestions and `cd` suggestions
  after a successful `mkdir`, accepted with Tab.
- **Built-in browser:** local HTML and web content, in-pane search, and link
  actions for external browser, tab, pane, or clipboard.
- **iOS remote:** pair an iPhone over the local network to view panes in the
  Mac's colors and type into them, with on-device Japanese IME conversion and a
  clear disconnected state, plus APNs push of Attention items so the phone
  alerts even with the remote app closed.
- **GIF recording:** records a pane for up to 60 seconds with sharp Retina
  output; the save dialog appears after recording stops.
- **Native settings:** English/Japanese UI, key-binding conflict detection,
  close confirmations, launch behavior, and signed in-app updates.

## Feature Guide

### Windows, tabs, and panes

Use windows, tabs, and panes directly; there is no separate workspace layer.
Tabs can be placed on the left, right, top, or bottom. Drag any part of a tab to
reorder it. A tab's context menu provides rename, path, Finder, move, close, and
pane-equalization actions, and a terminal pane's own context menu can close
that pane. The pane count is always shown, and tab indicators
also show zoom, recording, and actively processing agents. On macOS 26 and
later, the rename dialog gains an **Auto-Name** button: the on-device Apple
Intelligence model reads the focused terminal's recent output and fills the
field with a short suggested name — nothing is sent off the machine, and the
name is only applied when you press Save.

Splitting divides the focused pane in half. Resize panes by dragging their
divider, use **Equalize Panes** to distribute the available area, or toggle
**Pane Zoom** to temporarily fill the tab with the focused pane. Inactive panes
are dimmed and stop cursor blinking. **Swap Panes** (Window ▸ Pane menu,
Control-Command-S) lets you rearrange a tab's layout by clicking: the first
pane you click is highlighted with an accent border while a status hint
guides you to pick the second one, and clicking it swaps the two panes'
positions in place, split ratios included; click the same pane again, or
trigger the command a second time, to cancel. Once in Swap Panes mode, the
plain arrow keys move a lighter-bordered cursor between panes and Return
picks the cursored pane instead of clicking, so the whole flow works from
the keyboard alone. On macOS 26 and later,
**Explain Pane** (Window ▸ Pane menu, Control-Command-I) has the on-device Apple Intelligence model read
the focused terminal's recent output and explain what has been happening in it
in a floating panel — nothing leaves the machine. **Summarize Last Command**
(Window ▸ Pane menu, Control-Command-J) instead focuses on the most recent command:
a detailed on-device summary of its result that keeps the concrete numbers,
paths, and names, and explains each error — what it means, its likely cause,
and a possible fix. During a live resize, each pane briefly
shows its terminal grid size.

**Show All Panes** opens a compact switcher with the current command or agent
name and working directory. Selecting a row changes tabs and focuses that pane.

Closing a pane or tab keeps it around for the rest of the session: **Reopen
Closed Item** (Window menu, Command-Shift-T) brings back the most recently
closed pane or tab, scrollback, working directory, and agent resume info
included, and the **Recently Closed Items** submenu lists up to the last 20
closed items to reopen individually. This history lives in memory only — it
is not part of what is restored when Mytty relaunches, and closing a window
does not add to it.

### Shell and autocomplete

Each terminal pane starts a login shell in its saved working directory. Shell,
font, font size, cursor shape/blink, appearance, a Ghostty theme, custom colors,
and background opacity can be changed in **Settings > Shell** and apply to open
panes immediately. Font names are rendered in their own typeface and use a
localized family name when macOS provides one.

Programming ligatures are disabled by default so the terminal shows literal
characters — `->` never renders as a `→` glyph. To re-enable or customize them,
set your own `font-feature` in `~/.config/mytty/terminal.conf` (e.g.
`font-feature = calt`); Mytty only supplies the default when you have not.

Autocomplete learns submitted command history locally. It also proposes
`cd <directory>` after `mkdir <directory>` succeeds. A faded inline suggestion
is accepted with Tab; normal editing dismisses or updates it. It can be disabled
in Shell settings.

On macOS 26 and later, **Compose One-Liner** (Edit menu, Control-Command-K)
turns a natural-language request — e.g. "find files in this folder that
contain 'Test'" — into a shell one-liner using the on-device Apple
Intelligence model. The result appears read-only next to a Copy button and is
never executed; when the task cannot be done in a single command line, the
model says so instead. Nothing leaves the machine.

### Agents and Attention

Install an integration for each provider from **Settings > Agents**. Mytty
preserves unrelated provider configuration and can repair an installed hook.
The hook is inactive outside a Mytty pane, so using an agent in another terminal
does not require a Mytty event socket.

The active pane's agent name appears in the title/status area. When available,
the status bar overlays remaining percentages on compact quota meters and shows
the estimated session cost. Clicking the agent information offers **Copy
Session ID** when a session ID is known. A spinner appears only while the agent
is processing, not while it waits at a prompt.

Attention collects approval requests, input requests, completions, and failures.
Open it from the tab panel or with its shortcut, then use the return-arrow action
to move to the source shell; a clear-all button in its header marks everything
read at once. Focusing the originating pane marks its notifications
as read, and events from the pane you are actively watching arrive already read —
so the inbox is exactly what finished or asked for you in other tabs and panes.
Connection/disconnection events are not shown as notifications.

**Prevent Mac sleep for agents** has three modes: allow sleep, prevent only
while an agent is actively running a turn, or prevent for as long as an agent
CLI is open in a pane, even between turns. Mytty creates a sleep assertion
only while the selected condition is met, and that assertion holds off
**display** sleep as well as system sleep — not for visibility, but because
libghostty builds every surface's render loop on a display link that cannot
be created while no display is awake, so a Mac whose screen had slept could
not open a window, tab, or pane at all. The status-bar moon/sun
button shows the current mode and state, provides a tooltip, and opens a menu
to change the mode. While sleep prevention is in effect, Mytty also keeps the
Mac awake **with the lid closed**: on a MacBook without an external display,
closing the lid normally forces sleep regardless of assertions, so a bundled
privileged helper disables sleep system-wide for exactly as long as the
prevention condition holds, then restores it (also automatically if Mytty
crashes). The helper needs a one-time approval of Mytty's background item in
System Settings — no password prompts. Selecting a prevention mode first shows
an explanatory dialog that offers to open System Settings; until the approval
is granted, the tooltip also says what to allow. While the lid-closed override is armed, the status-bar icon
turns orange and its tooltip says so.

### AI control (mytty-ctl)

`mytty-ctl` is a local CLI that lets an AI agent running inside a Mytty pane
drive Mytty itself: list panes, open/split panes (optionally in a specific
working directory, e.g. a separate `git worktree`), type text or press a
named key, read a pane's screen, wait for a pane's tracked agent run to go
idle or need attention, close a pane, or focus one. Every Mytty pane's shell
gets `MYTTY_CTL_BIN` (the binary's path) and `MYTTY_CONTROL_SOCKET`
automatically, so no setup is required beyond having Mytty running.

This turns "run a team of subagents" into a scriptable pattern: an AI splits
off panes (each optionally its own provider — Claude Code, Codex, Cursor, ...),
starts an agent in each, waits for them in parallel, and reads back the
results — all as ordinary, visible panes a person can watch or interrupt,
unlike a hidden background subagent. See `docs/mytty-ctl.md` for the full
command reference, architecture, and worked examples, and the bundled
`mytty-panes` skill for ready-to-use recipes. The control socket is local and
unauthenticated by design, protected only by Unix file permissions
(`0600`) restricting it to the same local user — the same trust boundary as
any other same-user automation (e.g. CGEvent).

### Status bar and scheduled input

The status bar is optional. Repository and folder information is left-aligned;
agent information, sleep prevention, and scheduled input are right-aligned.
In a GitHub checkout, the GitHub button opens the remote repository and the
current branch appears beside it. The folder button reveals the active working
directory in Finder.

Use the clock menu to schedule text for the active pane. A schedule contains a
date/time, text, and an optional trailing newline. Existing entries can be
edited or deleted from the same menu. Past or completed entries are removed,
closing a pane removes its schedules, and nothing is sent if Mytty is not
running at the requested time.

### Browser and links

Open a local HTML file with Command-O. Browser panes include navigation, search,
and close controls. Control-F searches the focused terminal or browser pane.
Command-click a link to choose **Open in browser**, **Open in new tab**, **Open
in new pane (right)**, **Open in new pane (down)**, or **Copy link**. This also
works for hyperlinks whose visible text differs from the URL, and while a
full-screen app such as Claude Code is capturing the mouse.

### Recording and key display

Use **Start/Stop Recording** to capture the focused pane as a GIF. Recording
stops automatically after 60 seconds and then asks where to save the file. A
stop control appears on the tab while recording. When **Show pressed keys in
pane** is enabled, key labels appear below the cursor during normal use and are
included at the same position in recordings.

### iOS remote

Enable **Settings > iOS Remote Access**, generate a pairing code, and pair the
companion iOS app (`ios/MyttyRemote`) over the local network — the Mac is found
by Bonjour and the connection is paired and encrypted. The Mac listens on port
51820 (falling back to an automatic port when taken — Settings shows the
actual one), so over a VPN such as Tailscale the phone can pair by entering
the address directly; pairing attempts can be cancelled and give up after 30
seconds. From the phone you browse
windows, tabs, and panes and open a pane to watch it live: the pane renders in
the Mac's terminal colors, including bold, dim, and reverse-video text, with a
block cursor. Up to 10,000 lines of scrollback are mirrored to the phone. The
view follows new output only while you are at the bottom, so scrolling up
through the scrollback holds your reading position. Full-screen terminal apps
(agents, pagers, editors) have no scrollback to mirror, so scrolling such a
pane is forwarded to the Mac as mouse-wheel input and the app's own scrolling
— an agent's history view, for example — responds from the phone. Typing sends
input to the pane; Japanese composes through the
iPhone's IME (kanji conversion happens on the phone and only the committed text
is sent), and a control-key bar covers Ctrl, Option, arrows, and other named
keys. The bar's paste key sends the iPhone's clipboard to the pane as a
paste, and the copy button in the pane's toolbar opens a frozen snapshot of
the buffer where text can be selected and copied with the standard iOS
selection — or copied whole with **Copy All**. When the connection drops, the pane shows a banner, dims its stale
content, and disables input until you tap **Reconnect** — or until the app
comes back to the foreground, which reconnects on its own. Either way you stay
on the same pane; if that pane was closed on the Mac in the meantime, the app
falls back to the pane list, and to the tab list if the whole tab is
gone. Opening a browser pane shows its title and the page's current URL —
kept in sync as the Mac navigates — with buttons to open the same page in an
in-app Safari view on the phone or copy the URL. Registered Macs can be renamed and re-addressed later from the
phone's settings screen: each entry's label and connection method — Bonjour
service name, or a manual host and port — are editable without re-pairing.

#### Push notifications

Attention items also reach a paired iPhone through Apple Push Notification
service, so an agent that needs approval while you are away from the desk
alerts the phone even when the remote app is closed. The push fires whenever
Mytty is not the frontmost app — including the case where the pane is still
focused on screen, which is what walking away from a running agent looks
like — so it does not double up with the Mac's own banner.

The relay that carries them is a Cloudflare Worker
(`cloudflare/push-relay`), so nothing has to be configured on this Mac: the
phone registers with it directly and hands back only a handle.

Alert text never reaches the relay in the clear. The Mac seals it with the
key it and the phone established when they paired, and a notification
service extension on the phone unseals it just before iOS shows it. What
Cloudflare sees is a device token, a random Mac identifier, and ciphertext;
a phone that cannot decrypt falls back to a placeholder naming only the
kind of Attention.

Tapping the alert opens the app on the pane that raised it, connecting to
the right Mac and descending to its window and tab on the way. A pane that
has since closed leaves you at the Mac's session instead.

The toggle can be turned off to stop pushes without unpairing. Self-hosting
the relay — or running one at all, if you build the iOS app under your own
Apple Developer team — is documented in
[`cloudflare/push-relay/README.md`](cloudflare/push-relay/README.md).

### Settings and storage

Settings are organized into **General**, **Shell**, **Agents**, **Key Bindings**,
and **Update**. Key bindings can be recorded from the UI; conflicts identify the
other command, and pressing Delete while recording removes a binding.

Release data is kept in these locations:

| Data | Location |
| --- | --- |
| Application settings | `~/.config/mytty/config.toml` |
| Terminal settings | `~/.config/mytty/terminal.conf` |
| Agent settings | `~/.config/mytty/agents.toml` |
| Sessions, events, and schedules | `~/Library/Application Support/mytty/` |
| Logs | `~/Library/Logs/mytty/` |

Local debug runs are deliberately separate. `swift run Mytty` appears as
**Mytty Dev** with a `DEV` Dock badge and uses `mytty-dev` directories plus the
`com.m-tkg.mytty.dev` socket. It can run alongside an installed release without
sharing settings, sessions, or cached usage data. Provider hook installation is
shared because provider configuration is global; routing remains pane-scoped.

### Default shortcuts

All commands can be changed or cleared in **Settings > Key Bindings**.

| Command | Default shortcut |
| --- | --- |
| Settings | Command-, |
| New window / tab | Command-N / Command-T |
| Rename / close tab | Command-R / Command-W |
| Reopen closed item | Command-Shift-T |
| Split right / down | Command-D / Command-Shift-D |
| Focus pane | Command-Option-Arrow |
| Equalize panes | Control-Command-= |
| Toggle pane zoom | Control-Command-Return |
| Swap panes | Control-Command-S |
| Find in pane | Control-F |
| Show all panes | Control-Command-P |
| Command palette | Command-Shift-P |
| Close pane | Command-Shift-W |
| Toggle Attention | Command-Shift-A |
| Toggle tab panels | Command-B |
| Start/stop recording | Command-Shift-G |
| Explain pane (macOS 26+) | Control-Command-I |
| Summarize last command (macOS 26+) | Control-Command-J |
| Compose one-liner (macOS 26+) | Control-Command-K |

### Updates

Mytty checks GitHub Releases at launch and when About is opened. A newer signed
release can be checked for and installed from **About Mytty** or **Settings >
Update**. Automatic checks and a plain click of **Check for Updates** only
consider stable releases; Option-click **Check for Updates** to also consider
pre-releases (`x.y.z-beta.1`, `x.y.z-rc.2`, ...) and update to the newest one
found. Before replacement, Mytty verifies the download digest, bundle identity
and version, Developer ID team signature, nested code, and Gatekeeper
assessment. Automatic and manual self-update are disabled in Mytty Dev.

## Build

> **Building the iOS remote app with your own account?** Create
> `ios/MyttyRemote/Config/Local.xcconfig` first and set your own Team ID and
> bundle ID — see
> [Building with your own account](docs/building.md#building-with-your-own-account).

See [Building Mytty](docs/building.md) for prerequisites, libghostty setup,
tests, debug execution, application bundling, and the tag-based release flow.

Architecture and integration details are documented in
[`docs/design.md`](docs/design.md),
[`docs/agent-integrations.md`](docs/agent-integrations.md), and
[`docs/agent-events.md`](docs/agent-events.md).

## License

MIT
