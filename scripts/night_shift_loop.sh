#!/usr/bin/env bash
# night_shift_loop.sh — the Night Shift outer loop.
#
# Drives the ready-for-agent Issue queue one task at a time: selects the next
# grabbable Issue and hands it to the executor, draining back-to-back with no
# idle wait while work exists, sleeping ~5 min only when the queue is empty
# (serial v1). Holds no phase logic — that lives entirely in the executor
# (scripts/night_shift_run.sh, ADR-0023). The trigger label is ready-for-agent
# (the trigger label; #63 decided it stays `ready-for-agent` — ADR-0025).
#
# Usage:
#   night_shift_loop.sh                # loop (persistent poll, primary entry)
#   night_shift_loop.sh loop           # same as above
#   night_shift_loop.sh drain          # one drain pass then exit
#   night_shift_loop.sh select         # print the next grabbable Issue number
#
# Externals are dependency-injected (so the seams test offline):
#   NIGHT_SHIFT_GH            (default: gh)                 GitHub CLI
#   NIGHT_SHIFT_RUN           (default: $SCRIPT_DIR/night_shift_run.sh)  executor
#   NIGHT_SHIFT_ROOT          (default: repo root)           clone root
#   NIGHT_SHIFT_STATE_DIR     (default: $ROOT/.night-shift)  state store
#   NIGHT_SHIFT_TRIGGER_LABEL (default: ready-for-agent)     pickup trigger (ADR-0025)
#   NIGHT_SHIFT_CLAIM_LABEL   (default: in-progress)         claim label
#   NIGHT_SHIFT_POLL_INTERVAL (default: 300)                 seconds to sleep when idle
#   NIGHT_SHIFT_SLEEP         (default: sleep)               sleep binary (testable)
#   NIGHT_SHIFT_STOP_FILE     (default: $STATE_DIR/stop)     kill switch sentinel
#   NIGHT_SHIFT_CONCURRENCY   (default: 1)                   serial dial (v1 only)
#   NIGHT_SHIFT_MAX_POLLS     (default: "")                  empty = unbounded
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GH="${NIGHT_SHIFT_GH:-gh}"
RUN="${NIGHT_SHIFT_RUN:-$SCRIPT_DIR/night_shift_run.sh}"
ROOT="${NIGHT_SHIFT_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}"
TRIGGER_LABEL="${NIGHT_SHIFT_TRIGGER_LABEL:-ready-for-agent}"
CLAIM_LABEL="${NIGHT_SHIFT_CLAIM_LABEL:-in-progress}"
POLL_INTERVAL="${NIGHT_SHIFT_POLL_INTERVAL:-300}"
SLEEP="${NIGHT_SHIFT_SLEEP:-sleep}"
CONCURRENCY="${NIGHT_SHIFT_CONCURRENCY:-1}"
MAX_POLLS="${NIGHT_SHIFT_MAX_POLLS:-}"
export NIGHT_SHIFT_STATE_DIR="${NIGHT_SHIFT_STATE_DIR:-$ROOT/.night-shift}"
STOP_FILE="${NIGHT_SHIFT_STOP_FILE:-$NIGHT_SHIFT_STATE_DIR/stop}"
STORE="$SCRIPT_DIR/loop_state.sh"          # sibling loop-state script (night_shift_run.sh:43)

# --- selection seams ---------------------------------------------------------

_candidates_tsv() {
  "$GH" issue list \
    --label "$TRIGGER_LABEL" \
    --state open \
    --json number,labels \
    --jq '.[] | [.number, ([.labels[].name] | join(","))] | @tsv' \
    2>/dev/null || true
}

_terminal_for() {  # N → exit 0 if already terminal (PR open or escalated)
  "$RUN" snapshot "$1" 2>/dev/null | grep -qE '^(PR_OPEN|ESCALATED)=1$'
}

# select_issue [exclude_csv] — lowest grabbable Issue not present in the optional
# exclude set (comma-list of numbers dispatched this pass).
select_issue() {
  local exclude="${1:-}"
  while IFS=$'\t' read -r n labels; do
    [ -z "$n" ] && continue
    # skip Issues already dispatched this pass (caller's exclude set)
    case ",$exclude," in
      *",$n,"*) continue ;;
    esac
    # skip claimed
    case ",$labels," in
      *",$CLAIM_LABEL,"*) continue ;;
    esac
    # skip terminal (PR open or escalated)
    _terminal_for "$n" && continue
    printf '%s\n' "$n"
    return 0
  done < <(_candidates_tsv | sort -n)
}

# --- loop helpers ------------------------------------------------------------

_require_serial() {
  [ "$CONCURRENCY" = "1" ] || {
    echo "night_shift_loop: serial only in v1 (concurrency=$CONCURRENCY reserved for a later graduation)" >&2
    return 2
  }
}

_stopped() { [ -f "$STOP_FILE" ]; }

# _gc_closed_states — poll-time GC (#97): drop <N>.state for any task whose Issue is
# CLOSED (the same signal the dashboard uses). Keyed on Issue-CLOSED ONLY: a merged PR
# closes its Issue, so merge → close → next poll → GC. Escalated-but-open and
# PR-open-but-unmerged tasks keep their Issue OPEN and so survive (deleting either would
# re-escalate / re-plan from scratch). The *.state glob excludes the `stop` sentinel by
# construction. Fail-safe: delete ONLY on an exact CLOSED (allowlist) — a gh error/empty
# read is treated as "keep" (a lingering file is harmless; an erroneous delete is not).
_gc_closed_states() {
  local f n state
  for f in "$NIGHT_SHIFT_STATE_DIR"/*.state; do
    [ -e "$f" ] || continue                       # no matches → literal glob → skip
    n="$(basename "$f" .state)"
    case "$n" in ''|*[!0-9]*) continue ;; esac    # only Issue-numbered state files
    state="$("$GH" issue view "$n" --json state --jq .state 2>/dev/null || true)"
    if [ "$state" = "CLOSED" ]; then
      echo "gc: #$n closed — clearing loop state"
      bash "$STORE" clear "$n" || true
    fi
  done
}

# --- subcommands -------------------------------------------------------------

drain() {
  _require_serial || return $?
  _gc_closed_states                    # poll-time GC of closed-Issue loop state (#97)
  local dispatched=""
  while :; do
    if _stopped; then
      echo "kill switch: $STOP_FILE present — stopping"
      return 0
    fi
    n="$(select_issue "$dispatched")"
    if [ -z "$n" ]; then
      # No selectable Issue remains that we haven't already dispatched this pass —
      # forward progress is exhausted. If one is STILL selectable but was excluded,
      # its claim never stuck (best-effort `_claim` swallowed by `gh … || true`, or
      # the executor died pre-claim); log it as a diagnostic, but do NOT re-dispatch:
      # each Issue is dispatched at most once per pass (preserves the #81 H1 hot-spin
      # bound), and loop()'s idle sleep is the cross-pass backoff that gives the stuck
      # Issue one more try next poll. Skipping it here is what lets higher-numbered
      # ready Issues still drain (#84).
      # Only re-probe when we actually dispatched this pass: on an idle poll
      # (dispatched empty) nothing can be stuck-after-dispatch, so skip the
      # extra `gh` round the un-excluded select would otherwise cost every poll.
      if [ -n "$dispatched" ]; then
        local stuck; stuck="$(select_issue)"
        [ -n "$stuck" ] && echo "no progress on #$stuck (still selectable after dispatch) — ending drain pass to back off" >&2
      fi
      return 0
    fi
    echo "dispatch: #$n"
    rc=0
    "$RUN" "$n" || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "executor rc=$rc for #$n — task left claimed; continuing" >&2
    fi
    dispatched="${dispatched:+$dispatched,}$n"
  done
}

loop() {
  _require_serial || return $?
  trap 'echo "signal received — stopping loop"; exit 0' INT TERM
  polls=0
  while :; do
    if _stopped; then
      echo "kill switch: $STOP_FILE present — stopping loop"
      return 0
    fi
    drain
    polls=$((polls + 1))
    if [ -n "$MAX_POLLS" ] && [ "$polls" -ge "$MAX_POLLS" ]; then
      echo "reached MAX_POLLS=$MAX_POLLS — exiting"
      return 0
    fi
    echo "idle: sleeping ${POLL_INTERVAL}s before next poll"
    "$SLEEP" "$POLL_INTERVAL"
  done
}

usage() {
  echo "usage: $(basename "$0") [select|drain|loop]" >&2
}

# --- entry -------------------------------------------------------------------

main() {
  local cmd="${1:-}"
  case "$cmd" in
    select) select_issue ;;
    drain)  drain ;;
    loop)   loop ;;
    '')     loop ;;
    -h|--help) usage ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
