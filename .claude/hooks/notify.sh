#!/usr/bin/env bash
# notify.sh — Claude Code notification primitive (Channel A).
#
# One deep module owning two independent, error-swallowing sinks:
#   1. tmux window flag (+ terminal bell) — at-keyboard, per-project-window signal
#   2. network push via ntfy              — AFK truth, milestones only
#
# Contract: NEVER writes stdout, NEVER fails its caller. Every path exits 0.
# Levels (severity on the single tmux colour slot: fail > info > pass):
#   fail   red latch (floor) + bell + push          — a real gate failure
#   info   yellow (only if not already red) + bell  — permission/idle, at-keyboard
#   pass   bell + push, colour untouched            — green milestone (won't false-clear a peer fail)
#   clear  reset the flag (the only release)        — operator-triggered
#
# NOT set -e: a failing sink must never abort the next one or the caller.
set -u

level="${1:-info}"
title="${2:-Claude Code}"
message="${3:-}"

# Optional gitignored config (NTFY_TOPIC, NTFY_URL, …). Absent file is fine.
CONF="$(dirname "$0")/notify.local.conf"
[ -f "$CONF" ] && . "$CONF" 2>/dev/null || true

# --- tmux sink: window flag + bell (only meaningful inside tmux) ---
if [ -n "${TMUX:-}" ]; then
  # Resolve the calling agent's OWN window via its inherited $TMUX_PANE (no -t needed).
  {
    win="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
    case "$level" in
      clear)
        # The only thing that releases the latch: restore tmux defaults.
        tmux set-option -w -t "$win" -u @claude_attention 2>/dev/null || true
        tmux set-window-option -t "$win" -u window-status-style 2>/dev/null || true
        ;;
      fail)
        # Red is the floor — set unconditionally, never downgraded.
        tmux set-option -w -t "$win" @claude_attention fail 2>/dev/null || true
        tmux set-window-option -t "$win" window-status-style 'fg=red,bold' 2>/dev/null || true
        ;;
      info)
        # Yellow only if the window is not already red (don't downgrade a live fail).
        cur="$(tmux show-options -wv -t "$win" @claude_attention 2>/dev/null)"
        if [ "$cur" != "fail" ]; then
          tmux set-option -w -t "$win" @claude_attention info 2>/dev/null || true
          tmux set-window-option -t "$win" window-status-style 'fg=yellow,bold' 2>/dev/null || true
        fi
        ;;
      pass)
        # Colour untouched — a peer pass must not false-clear another pane's live fail.
        :
        ;;
    esac
  } 2>/dev/null || true

  # Bell for every level except clear.
  if [ "$level" != "clear" ]; then
    printf '\a' > "${NOTIFY_BELL_TARGET:-/dev/tty}" 2>/dev/null || true
  fi
fi

# --- network sink: ntfy push (milestones only: fail/pass; info/clear stay quiet) ---
if [ -n "${NTFY_TOPIC:-}" ]; then
  case "$level" in
    fail|pass)
      curl -fsS -m 5 -H "Title: $title" -d "$message" \
        "${NTFY_URL:-https://ntfy.sh}/$NTFY_TOPIC" >/dev/null 2>&1 || true
      ;;
  esac
fi

# Pushover is a config-only branch (out of scope to wire). To enable, add to
# notify.local.conf and uncomment a guarded curl to https://api.pushover.net here.

exit 0
