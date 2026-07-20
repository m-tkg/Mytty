---
name: verify
description: Steps for building and launching Mytty (macOS AppKit/SwiftUI terminal app) to verify GUI behavior against the real app.
---

# Verifying Mytty against the real app

## Build and launch

```bash
swift build
nohup .build/debug/Mytty > /tmp/mytty-dev.log 2>&1 &   # note the pid
```

- A debug build (not a `.app`) runs under `ApplicationPathProfile.development`,
  keeping its settings and state separate under `~/.config/mytty-dev` and
  `~/Library/Application Support/mytty-dev`. It doesn't interfere with the
  user's production Mytty (release profile).
- Windows from the previous dev session get restored, often stacked at the
  same coordinates.

## Automating GUI interaction

- `screencapture -x out.png` is pre-approved and works. Crop the output with
  `sips -c H W --cropOffset Y X` to save tokens.
- Synthesizing CGEvents (clicks, drags, key input) is also pre-approved.
  Write a `driver.swift` in the scratchpad and build it with
  `swiftc -O -o driver driver.swift` (from past sessions: `windows <pid>`
  lists CGWindowList window coordinates, `drag x1 y1 x2 y2 [ms]`,
  `path x1 y1 x2 y2 x3 y3` for a drag through waypoints,
  `key <pid> <keycode> cmd`, `activate <pid>`).
- Coordinate systems: CGWindowList and CGEvent agree on a top-left-origin
  point coordinate system. AppKit (e.g. `draggingSession(endedAt:)`) uses a
  bottom-left origin, so convert between them. The screen is 1512x982pt
  (2x Retina).
- Key codes: T=17, N=45, W=13. `postToPid` reaches the app even when it's in
  the background.

## Verification tips

- Judge window count changes by the line count from `driver windows <pid>`.
- The tab row's first line sits about 102pt below the sidebar's top edge
  (title bar + header); the row stride is 53pt for a vertical layout.
- When all tab titles are identical (e.g. "masaki"), verify reordering by
  the position change of the selection highlight instead.
- Quit with `kill <pid>`. The session is saved on quit.
