# Autocomplete Feasibility

Status: On hold (2026-07-16)

## Conclusion

An Otty-style inline autocomplete system is feasible, but it cannot be built
reliably from libghostty key events or screen scraping alone. Mytty needs a
shell bridge that reports the shell editor's authoritative input buffer and
cursor position.

## Recommended architecture

1. Start with local zsh sessions only.
2. Add a zsh ZLE integration that reports `BUFFER`, `CURSOR`, and prompt state
   over a persistent, per-surface IPC channel.
3. Continue using OSC 133 shell marks to distinguish prompts, input, command
   execution, and command completion.
4. Position AppKit overlays from libghostty's
   `ghostty_surface_ime_point` caret rectangle.
5. Draw inline ghost text and the candidate panel above the terminal surface;
   never inject unaccepted suggestions into the terminal grid or shell buffer.
6. Intercept Tab, Escape, Return, and arrow keys only while autocomplete owns
   an active suggestion UI. Disable it during IME composition and alternate
   screen applications.
7. Compile the MIT-licensed Fig-compatible completion specifications into a
   bundled, read-only database. Store learned data separately in Mytty's local
   SQLite database.

## Delivery stages

### Stage 1

- Local zsh sessions
- Static Fig-compatible command, subcommand, option, and argument suggestions
- File and directory candidates
- Inline ghost text and an eight-row candidate panel
- Tab to accept, Escape to dismiss, arrows to select, Return to accept
- Local command history ranked by frequency and recency
- Learn only successful commands
- Redact password, token, API-key, and similar option values before storage

tmux, SSH-hosted shells, bash, and fish are out of scope for this stage.

### Stage 2

- bash and fish bridges
- tmux integration
- Dynamic local candidates such as Git branches
- Configurable accept and panel shortcuts
- History ignore patterns and learned-data management UI

### Stage 3

- README command discovery
- Opt-in `--help` parsing in a restricted subprocess
- Completion database updates
- Command correction suggestions

## Rejected approach

Reconstructing the command line from `GhosttySurfaceView.keyDown` and visible
terminal text is not suitable for production. It loses authority when the
shell handles history, completion plugins, multiline editing, paste, vi mode,
IME, or cursor movement. libghostty exposes screen text and a caret rectangle,
but its embedded surface API does not expose the zsh ZLE input buffer.

## Main risks

- Coexisting with zsh-autosuggestions and other ZLE widget wrappers
- Keeping the shell bridge nonblocking and scoped to one surface
- Correct behavior through tmux and nested or remote shells
- Avoiding command-history capture of secrets
- Supporting dynamic Fig generators without embedding an unrestricted
  JavaScript runtime

## References

- Otty autocomplete: <https://docs.otty.sh/terminal-features/autocomplete>
- Otty shell integration: <https://docs.otty.sh/terminal-features/shell-integration>
- Fig-compatible specifications: <https://github.com/withfig/autocomplete>
- libghostty embedded API: `Vendor/ghostty/include/ghostty.h`
- Current terminal input adapter:
  `Sources/GhosttyAdapter/GhosttySurfaceView.swift`

