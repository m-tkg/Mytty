# Getting started with Mytty

日本語版は [getting-started_ja.md](getting-started_ja.md) にあります。

This tutorial installs Mytty, opens it for the first time, and walks through
splitting a window into tabs and panes. By the end you will have moved
between panes with the keyboard, zoomed and swapped them, and quit and
relaunched the app to see everything come back the way you left it.

## Install Mytty

Mytty needs macOS 15 or later on Apple Silicon. Download `Mytty.zip` from
[Releases](https://github.com/m-tkg/Mytty/releases), unzip it, and drag
`Mytty.app` into `/Applications`. The build is signed and notarized, so
double-clicking it opens the app directly with no Gatekeeper warning to click
through. If you would rather build from source, follow
[Build the macOS app from source](../how-to/build-macos-app.md) instead and come back here once you have a
working binary.

## Launch it

Open Mytty from `/Applications` or Spotlight. There is nothing to configure
first: the first window that appears already has your login shell running in
it, ready to take input. If this is the only thing you do today, you already
have a working terminal.

## Split the window into panes

Open a second tab with Command-T. You will see the new tab appear as a row in
the sidebar on the left rather than as a strip across the top of the window,
which is deliberate: long tab titles stay readable, and the list does not
reflow as it grows. Each row also shows how many panes that tab currently
holds.

Now press Command-D inside that tab. The focused pane splits in half,
left and right, and you have two panes to work in.

![Two tabs in the sidebar, with a pane split in two](../images/panes.png)

Try the following in order, on the tab you just split:

| What to try | Shortcut |
| --- | --- |
| Split down instead of right | Command-Shift-D |
| Move focus to the pane above/below/left/right | Command-Option-Arrow |
| Zoom the focused pane to fill the tab, then again to undo | Control-Command-Return |
| Equalize every pane's size | Control-Command-= |
| Close the focused pane | Command-Shift-W |

After closing a pane, press Command-Shift-T. Mytty brings back the pane you
just closed, scrollback included, in the same split position it had before.
The same shortcut works for a closed tab, and the Window menu's **Recently
Closed Items** submenu keeps the last 20 closed panes and tabs individually,
in case you closed more than one.

One shortcut worth trying regardless of what you were just doing is
Command-Shift-P: it opens a command palette over every menu command in the
app, filtered as you type. It is faster than the menu bar once you know
roughly what you are looking for, and a reasonable way to discover a command
whose exact name or shortcut you have forgotten.

![The command palette open over a pane, listing menu commands with their shortcuts](../images/command-palette.png)

If you have several panes open and lose track of which is which, Control-
Command-P opens **Show All Panes**, a switcher listing each pane's current
command or agent name alongside its working directory. Picking a row jumps
straight to that tab with the pane focused.

Once you have two or more panes side by side, Control-Command-S turns on
**Swap Panes**: the first pane you click gets an accent border, a status hint
asks you to pick a second one, and clicking that second pane exchanges the
two panes' positions, split ratios included. Arrow keys and Return work too,
so the whole thing is reachable without a mouse. Clicking the same pane again,
or triggering the command a second time, cancels it.

The bar along the bottom of the window follows whichever pane is focused: it
shows that pane's working directory, and its Git repository and branch when
the directory is inside a checkout.

## Quit and relaunch

Quit Mytty with Command-Q while you still have the tabs and panes from this
tutorial open, then start it again. Windows, tabs, panes, their split ratios,
and their working directories are all restored exactly as you left them, and
if you had an agent session running in a pane, it comes back resumable too.
Closing the app is not something you need to plan around.

## Where to go next

- [First agent session](first-agent-session.md) picks up from here and turns
  one of these panes into a Codex or Claude Code session.
- The [feature guide](../../README.md#feature-guide) documents every pane
  action, context menu, and shortcut, including the macOS 26-only ones like
  Explain Pane and Auto-Name that were skipped here.
