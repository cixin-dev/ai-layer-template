#!/usr/bin/env bash
# notify.sh — Claude Code notification primitive.
#
# One deep module owning two independent, error-swallowing transports:
#   1. terminal bell      — at-keyboard: sends BEL to the controlling tty. Under tmux,
#                           monitor-bell + window-status-bell-style render it in the status
#                           bar; outside tmux, the terminal emulator rings / flashes its own
#                           window. No custom window colour is set here (ADR-0021).
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

# --- terminal bell: BEL to the controlling tty ---------------------------------
# Works in any terminal emulator. Under tmux the window bell flag lights up the
# status bar (monitor-bell + window-status-bell-style); outside tmux the terminal
# emulator rings / flashes its own window. NOTIFY_BELL_TARGET overrides the target.
{ printf '\a' > "${NOTIFY_BELL_TARGET:-/dev/tty}"; } 2>/dev/null || true

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
