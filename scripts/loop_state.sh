#!/usr/bin/env bash
# loop_state.sh — durable per-task loop state (phase + attempts + escalated).
# State dir: ${NIGHT_SHIFT_STATE_DIR:-.night-shift}/<task>.state (key=value lines)
set -euo pipefail

STATE_DIR="${NIGHT_SHIFT_STATE_DIR:-.night-shift}"

_file() { printf '%s/%s.state' "$STATE_DIR" "$1"; }

_read_key() {
  local file="$1" key="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true
}

_write() {
  local file="$1" key="$2" val="$3"
  mkdir -p "$(dirname "$file")"
  local tmp; tmp="$(mktemp "${file}.XXXXXX")"
  # Keep the other key; replace (or add) this one.
  { grep -v "^${key}=" "$file" 2>/dev/null || true; printf '%s=%s\n' "$key" "$val"; } > "$tmp"
  mv "$tmp" "$file"
}

cmd="${1:-}"
task="${2:-}"

if [ -z "$cmd" ] || [ -z "$task" ] && [ "$cmd" != "--help" ]; then
  printf 'Usage: %s <get-phase|get-attempts|get-escalated|set-phase|set-escalated|incr-attempts|clear> <task> [phase]\n' "$(basename "$0")" >&2
  exit 2
fi

case "$cmd" in
  get-phase)
    _read_key "$(_file "$task")" phase
    ;;
  get-attempts)
    raw=$(_read_key "$(_file "$task")" attempts)
    if printf '%s' "$raw" | grep -qE '^[0-9]+$'; then
      printf '%s\n' "$raw"
    else
      printf '0\n'
    fi
    ;;
  get-escalated)
    raw=$(_read_key "$(_file "$task")" escalated)
    if [ "$raw" = "1" ]; then printf '1\n'; else printf '0\n'; fi
    ;;
  set-phase)
    phase="${3:-}"
    if [ -z "$phase" ]; then
      printf 'Usage: %s set-phase <task> <phase>\n' "$(basename "$0")" >&2
      exit 2
    fi
    _write "$(_file "$task")" phase "$phase"
    ;;
  set-escalated)
    _write "$(_file "$task")" escalated 1
    ;;
  clear)
    rm -f "$(_file "$task")"
    ;;
  incr-attempts)
    raw=$(_read_key "$(_file "$task")" attempts)
    if printf '%s' "$raw" | grep -qE '^[0-9]+$'; then
      n=$((raw + 1))
    else
      n=1
    fi
    _write "$(_file "$task")" attempts "$n"
    printf '%s\n' "$n"
    ;;
  *)
    printf 'Unknown subcommand: %s\n' "$cmd" >&2
    printf 'Usage: %s <get-phase|get-attempts|get-escalated|set-phase|set-escalated|incr-attempts|clear> <task> [phase]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
