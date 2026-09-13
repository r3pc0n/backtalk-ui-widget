# Backtalk Call (Omarchy bar widget)

A Quickshell bar widget for Omarchy: shows whether a voice call with your
[backtalk](https://github.com/jaredrhod/backtalk) agent is live, and opens a
small collapsible panel to start one, watch the transcript, type a message,
switch model/effort/voice/STT, adjust volume, or hang up — all without
leaving the bar.

- **Live/idle indicator** — the phone glyph tints to your accent color the
  moment a call is live, straight off backtalk's own transcript server.
- **Transcript view** — the last ~60 messages, rendered natively (no
  embedded browser), polling incrementally so it's cheap to leave running.
- **Type a message** — same input channel a spoken turn uses; works whether
  or not you're actually talking.
- **Settings view** (behind the `☰`) — model tier, reasoning effort, voice
  engine, speech-to-text engine, volume, auto-approve, and Hang Up. Every one
  of these just posts the same canned phrase backtalk's own transcript page
  sends (`"switch to the fast model"`, `"end voice mode"`, …) through its
  `/api/input` endpoint — no separate settings API to keep in sync.
- **No bridge process** — unlike some Omarchy widgets, this one needs
  nothing else running. backtalk's `launcher.py` (idle) and
  `transcript_server.py` (live) already answer everything on port 8793.

## Requirements

- Omarchy (Quickshell) shell.
- [backtalk](https://github.com/jaredrhod/backtalk) running locally, with its
  transcript UI enabled on the default port (8793).
- `hyprctl` and `jq` (both ship with Omarchy) — used by `open-or-focus.sh` to
  reuse an already-open Backtalk-UI webapp window instead of spawning a new
  browser tab, and to launch one via `omarchy-launch-webapp` if none is open.

## Install

```sh
omarchy plugin add git@github.com:r3pc0n/backtalk-ui-widget.git --enable --yes
```

Or manually:

```sh
git clone git@github.com:r3pc0n/backtalk-ui-widget.git ~/.config/omarchy/plugins/backtalk.call
omarchy plugin enable backtalk.call right
omarchy-restart-shell
```

**Always run `omarchy-restart-shell` after updating this plugin's files** —
Quickshell's hot-reload does not reliably replace an already-running widget
instance for a structural change (new click behavior, a new panel), only for
bindings a live instance already re-evaluates on its own. Trusting the
`"Local plugin changed, reloading"` debug line alone cost a real debugging
session the first time around.

## Usage

- **Click** the phone icon — open/close the panel.
- **Idle**: a Start Call button.
- **Live**: the transcript view by default — status strip, transcript,
  type-to-continue input.
- **`☰`** in the header — switch to the settings view (model, effort, voice
  engine, STT engine, volume, auto-approve, and Hang Up at the bottom,
  deliberately kept apart from the header's navigation icons).
- **`↗`** in the header — open the full Backtalk-UI page, for anything the
  compact panel doesn't cover.

## License

[MIT](LICENSE) © 2026 Des Octavis.
