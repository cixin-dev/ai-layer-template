#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOOP_STATE="$SCRIPT_DIR/loop_state.sh"
DECIDER="$SCRIPT_DIR/night_shift_decide.sh"

WORK="$(mktemp -d /tmp/nsretrytest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
export NIGHT_SHIFT_STATE_DIR="$WORK/state"

FAILURES=0
assert_eq() { [ "$1" = "$2" ] || { echo "FAIL: $3 (want '$2' got '$1')"; FAILURES=$((FAILURES+1)); }; }

# Helper: read recorded attempts for a task and feed the decider (separate process = restart-survival read).
decide_for_recorded() {
  local task="$1"
  local n; n="$(bash "$LOOP_STATE" get-attempts "$task")"
  env -i GATE=red REPORT_PRESENT=1 ATTEMPTS="$n" bash "$DECIDER"
}

# ---------------------------------------------------------------------------
# Drive the ladder through the real store (taskA)
# ---------------------------------------------------------------------------
bash "$LOOP_STATE" incr-attempts taskA >/dev/null
result="$(decide_for_recorded taskA)"
assert_eq "$result" "retry-reimplement" "taskA attempt 1 → retry-reimplement"

bash "$LOOP_STATE" incr-attempts taskA >/dev/null
result="$(decide_for_recorded taskA)"
assert_eq "$result" "retry-replan" "taskA attempt 2 → retry-replan (escalate-not-before)"

bash "$LOOP_STATE" incr-attempts taskA >/dev/null
result="$(decide_for_recorded taskA)"
assert_eq "$result" "escalate" "taskA attempt 3 → escalate (exactly at default K=3)"

# ---------------------------------------------------------------------------
# Idempotent restart: same recorded state → same decision
# ---------------------------------------------------------------------------
r1="$(decide_for_recorded taskA)"
r2="$(decide_for_recorded taskA)"
assert_eq "$r1" "escalate" "idempotent restart: first read after stop → escalate"
assert_eq "$r1" "$r2"      "idempotent restart: two reads of unchanged state agree"

# ---------------------------------------------------------------------------
# Namespacing: taskB is independent of taskA's count
# ---------------------------------------------------------------------------
bash "$LOOP_STATE" incr-attempts taskB >/dev/null
result="$(decide_for_recorded taskB)"
assert_eq "$result" "retry-reimplement" "taskB attempt 1 → retry-reimplement (unaffected by taskA)"

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
