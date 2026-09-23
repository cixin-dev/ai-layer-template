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
#   NIGHT_SHIFT_NOTIFY        (default: .claude/hooks/notify.sh)  sync-refusal alert
#   NIGHT_SHIFT_SYNC          (default: 1)                   0 = skip the per-pass clone
#                                                            sync (tests/dry-runs outside the clone)
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
NOTIFY="${NIGHT_SHIFT_NOTIFY:-$SCRIPT_DIR/../.claude/hooks/notify.sh}"
SYNC="${NIGHT_SHIFT_SYNC:-1}"
SYNC_MARK="$NIGHT_SHIFT_STATE_DIR/sync-refused"   # refusal-streak marker (notify once)

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

# _sync_main — fast-forward the clone's `main` to `origin/main` at the top of every pass,
# queue-independent. Nothing else keeps the clone current: only a PIV drive pulls, and a
# drive needs a ready Issue, so an idle queue froze the clone two months at 6a8cc5c while
# every merged loop/executor/command fix silently never ran (retroactive:
# night-shift-clone-auto-pull). Auto-pull is safe here — unlike from a hook (ADR-0029) —
# because the flock-held drain is the clone's only actor (ADR-0024). FF-only: a clone that
# cannot fast-forward (off main, dirty, diverged, fetch failing) is refused, never merged
# or reset. rc 0 = already current, 10 = advanced (caller re-execs), 1 = refused.
_sync_main() {
  local branch before err
  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  if [ "$branch" != "main" ]; then
    _sync_refused "clone is on '${branch:-detached HEAD}', not main"
    return 1
  fi
  before="$(git -C "$ROOT" rev-parse HEAD)"
  if ! err="$(git -C "$ROOT" fetch -q origin main 2>&1 \
              && git -C "$ROOT" merge -q --ff-only origin/main 2>&1)"; then
    # git leads with hint:/usage lines; the first fatal:/error: line is the reason.
    _sync_refused "$(grep -m1 -E '^(fatal|error):' <<< "$err" || head -n 1 <<< "$err")"
    return 1
  fi
  rm -f "$SYNC_MARK"
  [ "$(git -C "$ROOT" rev-parse HEAD)" = "$before" ] && return 0
  echo "sync: main ${before:0:7} → $(git -C "$ROOT" rev-parse --short HEAD) — re-exec on the pulled code"
  return 10
}

# _sync_refused REASON — loud on every refused pass; notify once per refusal streak (the
# marker), so a clone stuck for a night pings the operator once, not every 5 minutes.
_sync_refused() {
  echo "sync: REFUSED — $1 — no dispatch until the clone can fast-forward main" >&2
  [ -f "$SYNC_MARK" ] && return 0
  mkdir -p "$NIGHT_SHIFT_STATE_DIR" && : > "$SYNC_MARK"
  "$NOTIFY" fail "Night Shift sync refused" "$ROOT: $1 — no dispatch until main can fast-forward" || true
}

# --- subcommands -------------------------------------------------------------

drain() {
  _require_serial || return $?
  # Not while stopped: a quiesced clone is the operator's to touch (the HEAD race, ADR-0024).
  if [ "$SYNC" = "1" ] && ! _stopped; then
    local sync_rc=0
    _sync_main || sync_rc=$?
    # Advanced → finish this pass on the pulled code; a persistent loop() would otherwise
    # never re-read its own script. Refused → skip the pass (loud), retry next poll.
    [ "$sync_rc" -eq 10 ] && exec bash "$0" "${ENTRY_ARGS[@]}"
    [ "$sync_rc" -eq 0 ] || return 0
  fi
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
  ENTRY_ARGS=("$@")                    # drain's post-sync re-exec replays the entry verbatim
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
