# Keyboard shortcuts reference

Every shortcut below except **Toggle Attention** is a `MyTTYCommand` and
can be viewed, changed, or cleared in **Settings > Key Bindings**
(`KeyBindingSettingsCatalog.swift`, defaults in `KeyBinding.swift`). Two
commands, **Split Left** and **Split Up**, ship with no default binding.
They still appear in Key Bindings and can be assigned a key there.
Commands marked "macOS 26+" only appear in the menu and in Key Bindings
on macOS 26 and later, since they run on the on-device Foundation Models
framework.

## Application

| Command | Default shortcut |
| --- | --- |
| Settings | Command-, |
| Quit Mytty | Command-Q |
| New Window | Command-N |
| Next Window | Command-` |
| Previous Window | Command-Shift-` |
| Open HTML File | Command-O |
| Command Palette | Command-Shift-P |
| Compose One-Liner (macOS 26+) | Control-Command-K |

## Tabs

| Command | Default shortcut |
| --- | --- |
| New Tab | Command-T |
| Rename Tab | Command-R |
| Close Tab | Command-W |
| Reopen Closed Item | Command-Shift-T |
| Toggle Tab Panels | Command-B |
| Next Tab | Control-Tab |
| Previous Tab | Control-Shift-Tab |
| Go to Tab 1-9 | Command-1 ... Command-9 |

Tab positions are renumbered top to bottom whenever a tab opens, closes, or
gets dragged to a new spot, and the sidebar shows the current number under
each tab's drag handle. Command-9 jumps to the 9th tab specifically -- with
fewer than 9 tabs open, it does nothing rather than jump to the last one.

## Panes

| Command | Default shortcut |
| --- | --- |
| Show All Panes | Control-Command-P |
| Split Left | not set |
| Split Right | Command-D |
| Split Up | not set |
| Split Down | Command-Shift-D |
| Focus Left | Command-Option-Left |
| Focus Right | Command-Option-Right |
| Focus Up | Command-Option-Up |
| Focus Down | Command-Option-Down |
| Equalize Panes | Control-Command-= |
| Toggle Pane Zoom | Control-Command-Return |
| Swap Panes | Control-Command-S |
| Find in Pane | Control-F |
| Close Pane | Command-Shift-W |
| Explain Pane (macOS 26+) | Control-Command-I |
| Summarize Last Command (macOS 26+) | Control-Command-J |

## Terminal Recording

| Command | Default shortcut |
| --- | --- |
| Start/Stop Recording | Command-Shift-G |

## Menu commands without a customizable binding

**Toggle Attention** appears in the View menu (Attention drawer show/hide)
but is not a `MyTTYCommand`: it has no entry in
`KeyBindingSettingsCatalog`, no default in
`MyTTYCommand.defaultKeyBindings`, and the menu item itself is built with
an empty `keyEquivalent` in `MainMenuBuilder.swift`. It cannot currently
be bound to a key from Settings, and no other key monitor in the codebase
binds one either. `config.toml`'s schema reserves a
`keybinding.toggle-attention` key for this command, but no code path
reads or writes it, so a hand-edited value in that file would have no
effect. This means the shortcut has no default keystroke in the current
build, contrary to some in-app and documentation references to
Command-Shift-A.

## Notation

`Command-Option-Arrow` in prose refers to all four arrow directions bound
individually as above. Key names shown for recorded/custom bindings match
what `KeyBindingRecorder` displays: arrows render as `←↑→↓`, Return as
`↩`, and modifiers appear in the fixed order Control (`⌃`) - Option
(`⌥`) - Shift (`⇧`) - Command (`⌘`).
