#!/usr/bin/env bash
# notify.sh — Claude Code notification primitive.
#
# One deep module owning two independent, error-swallowing transports:
#   1. tmux bell          — at-keyboard: trips the agent's OWN tmux window bell flag.
#                           tmux's `monitor-bell` + the operator's `window-status-bell-style`
#                           render it in the status bar, and tmux auto-clears it when the
#                           window is visited. No custom window colour is set here (ADR-0021).
#   2. network push (ntfy) — AFK truth, milestones only; carries the severity.
#
# Contract: NEVER writes stdout, NEVER fails its caller. Every path exits 0.
# Levels (the issue signature; severity lives in the push, not the window):
#   fail   bell + push   — a real gate failure
#   pass   bell + push   — a green milestone (PR ready)
#   info   bell only     — permission/idle, at-keyboard; never hits the phone
#
# NOT set -e: a failing transport must never abort the next one or the caller.
set -u

level="${1:-info}"
title="${2:-Claude Code}"
message="${3:-}"

# Optional gitignored config (NTFY_TOPIC, NTFY_URL, …). Absent file is fine.
CONF="$(dirname "$0")/notify.local.conf"
[ -f "$CONF" ] && . "$CONF" 2>/dev/null || true

# --- tmux transport: ring the bell → tmux flags the agent's own window ----------
# The BEL goes to the hook's controlling tty (the agent's pane), so tmux attributes
# the window bell flag to the right window with no -t resolution, and visiting the
# window clears it — tmux's native per-window latch, no explicit release needed.
if [ -n "${TMUX:-}" ]; then
  printf '\a' > "${NOTIFY_BELL_TARGET:-/dev/tty}" 2>/dev/null || true
fi

# --- network transport: ntfy push (milestones only: fail/pass; info stays quiet) -
if [ -n "${NTFY_TOPIC:-}" ]; then
  case "$level" in
    fail|pass)
      curl -fsS -m 5 -H "Title: $title" --data-raw "$message" \
        "${NTFY_URL:-https://ntfy.sh}/$NTFY_TOPIC" >/dev/null 2>&1 || true
      ;;
  esac
fi

# Pushover is a config-only branch (out of scope to wire). To enable, add to
# notify.local.conf and uncomment a guarded curl to https://api.pushover.net here.

exit 0
