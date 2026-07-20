# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Mytty is an Apple Silicon, macOS-native terminal (macOS 15+) for AI-assisted workflows. It embeds libghostty for terminal emulation/rendering and adds tabs, panes, agent status, an Attention Inbox, and session restoration — deliberately without a workspace abstraction. A companion iOS remote app lives in `ios/MyttyRemote`.

## Commands

```sh
swift build                 # debug build (.build/debug/Mytty)
swift test                  # full test suite (also: make test)
swift test --filter "Codex session inspection"   # one suite/test by name
swift run Mytty             # run the dev app
scripts/bundle.sh debug     # packaged "Mytty Dev.app" in dist/ (make mac-app)
make ios                    # iOS Simulator build (regenerates Xcode project via xcodegen)
make release VERSION=x.y.z  # test, push main, tag vx.y.z -> CI builds/notarizes Mytty.zip
make release VERSION=x.y.z-beta.1   # same, but publishes a GitHub *pre-release*
```

A `VERSION` with a pre-release suffix (`-beta.1`, `-rc.2`, …) publishes a
GitHub pre-release instead of a stable release: `scripts/release.sh` accepts
exactly the versions `ApplicationVersion` can parse, and the Release workflow
passes `--prerelease` to `gh release create` when the tag has a suffix. The
in-app updater only offers pre-releases when the user Option-clicks **Check
for Updates**; a plain check and the automatic launch/About checks stay on
stable releases. Only the macOS app ships through this flow — the iOS remote
app in `ios/MyttyRemote` is not part of the Mac release.

The iOS app ships through Xcode Cloud, which builds the **checked-in**
`ios/MyttyRemote/MyttyRemote.xcodeproj` — it does not run xcodegen. After
adding or removing a Swift file under `ios/MyttyRemote`, run `make ios` and
commit the regenerated `project.pbxproj` together with the file, or the
Xcode Cloud build fails with "Cannot find … in scope".

One-time prerequisite after cloning or after changing the Ghostty revision (needs Homebrew `zig@0.15`):

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh    # builds Vendor/ghostty/macos/GhosttyKit.xcframework
```

- Debug builds run as **Mytty Dev** and isolate all state under `~/.config/mytty-dev/`, `~/Library/Application Support/mytty-dev/`, etc., so they never disturb an installed release. Agent hook installation is shared (providers use global user config).
- To verify GUI behavior in the running app, use the `verify` skill (`.claude/skills/verify/SKILL.md`): build, launch `.build/debug/Mytty`, drive it with CGEvent/screencapture.
- Releases only happen from a clean `main` via `scripts/release.sh`; the GitHub Actions Release workflow re-runs `swift test` plus `Tests/ReleasePackagingTests.sh` before packaging.

## Architecture

SwiftPM package with strict target boundaries (`Package.swift`):

- **`MyTTYApp`** — the macOS app. AppKit owns windows, menus, focus, keyboard routing, IME, and terminal hosts; SwiftUI owns Settings, the tab sidebar, and the Attention drawer. `TerminalWindowController` is the hub: it owns per-concern collaborators (`AgentStatusPollingCoordinator`, `AgentUsagePollingCoordinator`, `RepositoryStatusCoordinator`, `PaneLayoutController`, `TerminalAutocompleteCoordinator`, `TerminalRecordingCoordinator`, `ScheduledInputCoordinator`, `RemotePaneBridge`, `TabDragController`) and wires their output into surfaces and the status bar; `AppDelegate` likewise delegates menu construction (`MainMenuBuilder`), window/session lifecycle (`WindowSessionCoordinator`), updates (`ApplicationUpdateCoordinator`), and the remote-access server delegate (`RemoteAccessCoordinator`).
- **`GhosttyAdapter`** — the only target allowed to touch Ghostty types; it wraps the pinned `GhosttyKit.xcframework` (built from the `Vendor/ghostty` submodule plus `Patches/`). Keyboard input, IME, resize, and rendering must not pass through global SwiftUI or observable app state.
- **`MyTTYCore`** — platform-neutral logic (Foundation only): tab/session model (`TabSession`, `SessionSnapshot`), agent event protocol and reducers, SQLite repositories, preferences, and the provider-specific `*SessionInspector`/`*UsageProbe` implementations plus `AgentSessionDatabase`.
- **`MyTTYAgentHook`** — the `mytty-agent-hook` helper binary that provider hooks invoke; it forwards events to the app.
- **`MyTTYClamshellHelper`** — the `mytty-clamshell-helper` privileged daemon (SMAppService/XPC) that runs `pmset disablesleep` for lid-closed keep-awake; its testable state machine lives in MyTTYCore (`ClamshellHelperCore`).
- **`MyTTYRemoteKit`** — shared code for the iOS remote (pairing, secure channel).

### Agent integration model

Agent state is **event-driven, never scraped from terminal output**. Enabling a provider in Settings installs hooks into that provider's global config (`~/.codex/hooks.json`, `~/.claude/settings.json`, etc.); the hooks call `mytty-agent-hook`, which sends versioned, idempotent events over a pane-scoped Unix socket (each surface gets its own `MYTTY_*` environment). An append-only event log plus a pure reducer derive the run state; Attention policy derives inbox items from that. See `docs/reference/agent-event-protocol.md` and `docs/reference/agent-providers.md` (the latter documents the per-provider lifecycle mapping and status-bar data sources).

Complementing the hooks, `TerminalWindowController`'s `AgentStatusPollingCoordinator` polls each pane's foreground process (0.5s) and:

- detects the provider from the executable/args (`TerminalAgentProcessDetector`);
- resolves that provider's `AgentProviderRuntime` (one implementation per provider, `AgentProviderRuntime.swift`, registered in `AgentProviderRuntimeRegistry`), which reads the in-use model and context remaining via that provider's `*SessionInspector` (MyTTYCore; Codex transcript fds, Claude Code project transcripts, OpenCode/Cursor SQLite, Antigravity settings) — throttled or fingerprint-cached (`AgentSessionThrottleCache`) because polling is on the main thread.

`AgentUsagePollingCoordinator` loads quota/cost meters the same way, via `NativeAgentUsageLoader` and the parallel `AgentProviderUsageSource` registry over each provider's `*UsageProbe` (MyTTYCore).

`AgentSessionDatabase` (MyTTYCore) is the shared read-only SQLite helper; it falls back to an `immutable=1` connection for WAL databases whose sidecars were checkpointed away — reuse it instead of opening SQLite directly.

## Workflow rules

- **Open a PR for every change.** All work — new features and fixes alike — goes through its own branch and pull request; do not push commits directly to `main`. Build and test the change, commit it as soon as it's finished, then open a PR and merge only after review. Don't let several changes pile up in one PR; interleaved edits in shared files (e.g. `PaneDetailView.swift`) then cannot be split cleanly.
- **Document features in the README.** When you implement a user-facing feature, add it to `README.md`, and keep `README.md` and `README_ja.md` in sync — the two must always describe the same behavior. `Tests/ReleasePackagingTests.sh` checks their required headings.
- **Gate macOS 26+ features.** Features that require macOS 26+ (notably anything built on Foundation Models) must be conditionally available so they only appear on macOS 26 and later — guard with `if #available(macOS 26, *)` / `@available` and hide the UI on older systems. The app's baseline is macOS 15, so such features are additive, never required.

## Conventions that matter here

- Tests use Swift Testing (`@Test` / `#expect`), one suite per file mirroring the source file name. Tests must not depend on paths that only exist on the developer's machine — CI runs as a different user, and fixtures should reproduce "path does not exist on disk" conditions deliberately (see `CursorSessionInspectorTests`).
- Parsers of external agent data (transcripts, hook payloads) validate everything: length-check identifiers, reject control characters, tolerate malformed JSON lines, and clamp derived percentages. Follow the existing `AgentSessionValidation` / inspector patterns.
- Provider config installers must preserve unrelated user configuration, write atomically, and never replace malformed JSON.
- UI strings go through `MyTTYLocalization` (English/Japanese); check `Tests/MyTTYAppTests/LocalizationTests.swift` when adding keys.
