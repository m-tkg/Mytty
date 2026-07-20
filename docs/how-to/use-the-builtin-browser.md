# Use the built-in browser

Mytty can open a browser pane alongside your terminals, useful for local
docs or a preview server without leaving the app. This is how to open one,
search inside it, and follow links from a terminal.

## Open a local file

Press Command-O and pick an HTML file. It opens in a new browser pane with
its own navigation, search, and close controls, sitting next to your
terminal panes like any other split.

## Search the focused pane

Control-F opens a search field for whichever pane is focused, terminal or
browser. It's the same shortcut either way, so you don't need to remember a
different one depending on what kind of pane you're looking at.

## Follow a link from a terminal

Command-click a link in a terminal pane to get a small menu:

- **Open in browser** opens it in a new browser pane
- **Open in new tab**
- **Open in new pane (right)** / **Open in new pane (down)**
- **Copy link**

This works even when the visible text of a hyperlink differs from the actual
URL underneath it, and it still works while a full-screen app such as Claude
Code is capturing the mouse: Command-click passes through to Mytty's link
handling instead of being swallowed by the foreground app.
