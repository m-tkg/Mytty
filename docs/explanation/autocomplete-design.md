# Autocomplete design

日本語版は [autocomplete-design_ja.md](autocomplete-design_ja.md) にあります。

Mytty's inline autocomplete shipped as a feature (see the "Local autocomplete" line in `README.md` and the implementation in `Sources/MyTTYApp/TerminalAutocomplete.swift` and `TerminalAutocompleteCoordinator.swift`). This page explains the design choices behind it, including where the shipped feature is deliberately smaller than the original feasibility study proposed.

## What actually shipped

Autocomplete in Mytty offers exactly one inline suggestion at a time, rendered as faded ghost text right after the cursor, accepted with Tab. It comes from two sources only. As a pane learns which commands exit successfully, typing a prefix of one of the last 200 such commands suggests the rest of it. Separately, after `mkdir <path>` succeeds, it suggests `cd <path>` as the next command.

There is no candidate panel, no static command/flag/argument database, and no persistence across app restarts; the learned command list lives in memory for the lifetime of the pane. This is considerably smaller than the Fig-compatible, multi-stage system an earlier feasibility study sketched out (its status line said "on hold", which was already stale by the time this page was written). The gap between that plan and what shipped is itself the interesting design story, not a shortfall to apologize for.

## Tracking the input buffer without a shell bridge

The feasibility study's core finding was that reconstructing the shell's input buffer from libghostty key events and screen text is unreliable in general: it loses authority the moment the shell handles history, completion plugins, multiline editing, paste, vi mode, or cursor movement itself. Its recommendation was a zsh ZLE (Zsh Line Editor) integration that would report the shell's actual `BUFFER` and `CURSOR` over a persistent per-surface channel, giving Mytty an authoritative view instead of a guess.

That bridge was never built. What shipped instead is closer to the approach the feasibility study rejected, but made safe by admitting when it does not know the buffer rather than pretending it does. `TerminalAutocompleteSession` (in `TerminalAutocomplete.swift`) mirrors what it believes the current line contains by watching key events through `TerminalAutocompleteEventMapper`: printable text appends to a local `currentInput` string, delete removes from the end, Return or Enter commits it as a submitted command. The moment it sees something it cannot faithfully track (arrow keys, Control/Option-modified navigation, marked text during IME composition), it sets an `inputIsReliable` flag to `false` and stops offering suggestions until the line resets (Return, or an explicit reset like Control-U). A wrong guess never reaches the screen; the session just goes quiet.

This works because the feature's blast radius is small by construction. The suggestion is a single line of ghost text at the cursor, any keystroke other than Tab dismisses or updates it, and nothing is ever injected into the terminal without the user pressing Tab. A shadow buffer that is sometimes wrong is tolerable when being wrong just means the suggestion disappears; it would not be tolerable for something that edited the terminal on its own. That tolerance is also why a shell-specific bridge turned out to be unnecessary: the shipped mechanism does not care whether the pane is running zsh, bash, or fish, because it never talks to the shell at all. It only reads NSEvents at the AppKit layer, which is also why the original stage plan (zsh first, bash and fish as a later stage) does not apply to what actually exists; there was no shell-specific integration to extend in the first place.

## Detecting command completion

Knowing when a command finished, and with what exit code, matters for deciding whether to learn it into history and whether to offer the `mkdir` → `cd` follow-up. Mytty does not parse OSC 133 shell-integration marks itself. libghostty already tracks them internally and surfaces a structured `GHOSTTY_ACTION_COMMAND_FINISHED` action with an exit code and duration; `GhosttyRuntime` forwards it to `GhosttySurfaceView.receiveCommandFinished`, which becomes a `.commandFinished` event that `TerminalWindowController` routes to `TerminalAutocompleteCoordinator.handleCommandFinished`. Consuming a structured action from the adapter boundary, instead of scanning the terminal's OSC stream a second time in `MyTTYApp`, keeps that parsing inside `GhosttyAdapter` where all Ghostty-specific handling belongs (see [architecture.md](architecture.md) on why Ghostty types stay behind that one boundary).

## Positioning the overlay

The ghost-text label has to sit exactly where the shell's own cursor is, one cell to the right of the last typed character, tracking font size and window resizes without visible lag. `GhosttySurfaceView.terminalCursorRect` gets this from libghostty directly via `ghostty_surface_ime_point`, the same caret rectangle IME composition uses to place its candidate window. Reusing that call rather than deriving a cursor position from the text grid separately means the autocomplete overlay and IME composition can never disagree about where the cursor actually is, since they read the same coordinate.

## What was deliberately left out

The feasibility study's later stages proposed bash and fish bridges, tmux support, dynamic candidates such as Git branches, a bundled MIT-licensed Fig-compatible completion database, and `--help` parsing for command discovery. None of that shipped, and none of it is a gap in an otherwise larger implementation; the design that did ship does not have a slot to plug a completion database into; it only ever offers one thing at a time, sourced from what the pane itself has already done. Extending it toward static completions would mean building the candidate panel and keyboard navigation the current version intentionally does not have, which is a different, larger feature than what "Local autocomplete" describes today.

Command history learning also intentionally has a narrow safety net: `TerminalAutocompleteEngine` and `TerminalAutocompleteSession` only ever store the literal command line, and only after it exits `0`. There is no redaction pass for secrets in flags or arguments, so the practical mitigation is scope, not filtering: nothing is written to disk, the list caps at 200 entries in memory, and it disappears when the pane closes.
