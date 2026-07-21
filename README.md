[日本語](README_ja.md)

# Mytty

**New here? Start with the [tutorials](docs/README.md#tutorials).**

## Overview

Mytty is an Apple Silicon, macOS-native terminal for an AI-assisted workflow.
It embeds libghostty for Metal-accelerated terminal rendering and uses AppKit,
SwiftUI, and WebKit for its surrounding interface. The terminal remains the
primary surface: Mytty adds tabs, panes, agent status, an Attention Inbox, and
small workflow tools without introducing a workspace abstraction.

Mytty supports Codex, Claude Code, OpenCode, Antigravity (including the
standalone Gemini CLI), and Cursor. Provider integrations deliver structured
events through a pane-scoped Unix socket, so Mytty can associate an agent
request with the correct pane without parsing human-readable terminal output.

The current release requires macOS 15 or later and Apple Silicon.

## Features

- **Ghostty terminal engine:** libghostty rendering, native IME, themes, and
  configurable fonts, cursor, opacity, and appearance.
- **Tabs and panes:** splits in four directions, drag-to-reorder tabs, pane
  zoom, equalized layouts, and an all-panes switcher. In a split tab the
  focused pane is outlined, with a configurable color and width, alongside
  the dimming applied to the inactive ones. Tabs are numbered in the
  sidebar and jump directly with Command-1 through Command-9.
- **Agent-aware status and Attention Inbox:** active agent, session cost,
  quota meters, and a persistent inbox of approval, input, success, and
  failure events that jump straight to the pane that raised them.
- **AI control (`mytty-ctl`):** a local CLI, usable from any pane with no
  setup, that lets an agent open panes, drive them, and read them back, so a
  team of subagents runs as ordinary, visible panes instead of a hidden
  background process. Run `mytty-ctl guide` for the full playbook -- it
  works the same from any project, not just this one. Mytty can also teach
  Claude Code and Codex to discover it on their own (a Settings toggle,
  on by default) by writing a short pointer into each provider's global
  configuration.
- **Session restoration, local autocomplete, a built-in browser, GIF
  recording, and an iOS remote app** with APNs push for Attention items.

See the [documentation](docs/README.md) for everything else: tutorials,
how-to guides, reference pages, and the design rationale behind each part.

## Documentation

Full documentation lives under [`docs/`](docs/README.md), split into four
sections:

- [Tutorials](docs/README.md#tutorials) to learn Mytty by using it
- [How-to guides](docs/README.md#how-to-guides) for a specific task
- [Reference](docs/README.md#reference) for exact settings, commands, and
  protocols
- [Explanation](docs/README.md#explanation) for why Mytty works this way

## Build

See [Build the macOS app from source](docs/how-to/build-macos-app.md) for
prerequisites, libghostty setup, tests, and application bundling, and
[Release a version](docs/how-to/release-a-version.md) for the tag-based
release flow.

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh
swift test
swift run Mytty
```

## License

MIT
