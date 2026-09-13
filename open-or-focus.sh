#!/usr/bin/env bash
# Clicking the aura.call widget while a call is live should show the
# transcript page Youri already has open in Chromium (installed as a
# webapp via Backtalk-UI.desktop / omarchy-launch-webapp), not spawn a
# second window in his default browser. Chromium gives every 127.0.0.1
# --app window the SAME window class ("chrome-127.0.0.1__-Default" --
# confirmed live, shared with the Vault Graph webapp too), so matching
# has to be on window title instead, which the transcript page sets once
# and never changes (backtalk/backtalk/transcript_web/index.html:6).
#
# This machine's Hyprland is on the Lua-config build (see "This Machine
# (E490)" in the vault): the classic `hyprctl dispatch focuswindow
# "title:^...$"` CLI form no longer works at all -- it gets fed through
# the Lua evaluator and fails as a syntax error. The real runtime call is
# `hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'title:^...$' }))"`.
# Confirmed live: `window = "x"` is the field name (verified by deliberately
# passing wrong field names until Hyprland's own error message named the
# valid ones: direction, monitor, window, urgent_or_last, last).
set -euo pipefail

TITLE="backtalk — transcript"

if hyprctl clients -j 2>/dev/null | jq -e --arg t "$TITLE" 'any(.[]; .title == $t)' >/dev/null 2>&1; then
  hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'title:^${TITLE}\$' }))" >/dev/null 2>&1
else
  omarchy-launch-webapp "http://127.0.0.1:8793/"
fi
