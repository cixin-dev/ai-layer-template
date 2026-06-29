#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STORE="$SCRIPT_DIR/loop_state.sh"

WORK="$(mktemp -d /tmp/loopstatetest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
export NIGHT_SHIFT_STATE_DIR="$WORK/state"

assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3 (want '$2' got '$1')"
    FAILURES=$((FAILURES + 1))
  fi
}

# (a) get-attempts unknown task → 0
got=$(bash "$STORE" get-attempts task-a)
assert_eq "$got" "0" "(a) get-attempts unknown task → 0"

# (b) get-phase unknown task → empty
got=$(bash "$STORE" get-phase task-b)
assert_eq "$got" "" "(b) get-phase unknown task → empty"

# (c) set-phase then get-phase → write→read
bash "$STORE" set-phase task-c implement
got=$(bash "$STORE" get-phase task-c)
assert_eq "$got" "implement" "(c) set-phase/get-phase write→read"

# (d) incr-attempts from nothing → 1; again → 2
got1=$(bash "$STORE" incr-attempts task-d)
assert_eq "$got1" "1" "(d) first incr-attempts → 1"
got2=$(bash "$STORE" incr-attempts task-d)
assert_eq "$got2" "2" "(d) second incr-attempts → 2"
got3=$(bash "$STORE" get-attempts task-d)
assert_eq "$got3" "2" "(d) get-attempts after two incrs → 2"

# (e) restart-survival: writes from prior calls read back intact in a fresh invocation
bash "$STORE" set-phase task-e validate
bash "$STORE" incr-attempts task-e >/dev/null
bash "$STORE" incr-attempts task-e >/dev/null
phase_e=$(bash "$STORE" get-phase task-e)
attempts_e=$(bash "$STORE" get-attempts task-e)
assert_eq "$phase_e" "validate" "(e) restart-survival: phase survives"
assert_eq "$attempts_e" "2" "(e) restart-survival: attempts survive"

# (f) namespacing: task A and task B are independent
bash "$STORE" set-phase task-f1 plan
bash "$STORE" incr-attempts task-f1 >/dev/null
bash "$STORE" incr-attempts task-f1 >/dev/null
bash "$STORE" set-phase task-f2 review
phase_f1=$(bash "$STORE" get-phase task-f1)
phase_f2=$(bash "$STORE" get-phase task-f2)
attempts_f1=$(bash "$STORE" get-attempts task-f1)
attempts_f2=$(bash "$STORE" get-attempts task-f2)
assert_eq "$phase_f1" "plan" "(f) task-f1 phase unaffected by task-f2"
assert_eq "$phase_f2" "review" "(f) task-f2 phase unaffected by task-f1"
assert_eq "$attempts_f1" "2" "(f) task-f1 attempts unaffected"
assert_eq "$attempts_f2" "0" "(f) task-f2 attempts default 0"

# (g) corrupt value: write attempts=oops → get-attempts → 0
mkdir -p "$NIGHT_SHIFT_STATE_DIR"
printf 'phase=\nattempts=oops\n' > "$NIGHT_SHIFT_STATE_DIR/task-g.state"
got=$(bash "$STORE" get-attempts task-g)
assert_eq "$got" "0" "(g) corrupt attempts value → fallback 0"

# (h) idempotent read: two consecutive get-attempts on unchanged state → identical
bash "$STORE" incr-attempts task-h >/dev/null
r1=$(bash "$STORE" get-attempts task-h)
r2=$(bash "$STORE" get-attempts task-h)
assert_eq "$r1" "$r2" "(h) idempotent read: two reads agree"

# (i) non-clobber: set-phase keeps attempts; incr-attempts keeps phase
bash "$STORE" incr-attempts task-i >/dev/null
bash "$STORE" incr-attempts task-i >/dev/null
bash "$STORE" set-phase task-i implement
attempts_i=$(bash "$STORE" get-attempts task-i)
assert_eq "$attempts_i" "2" "(i) set-phase does not clobber attempts"
bash "$STORE" incr-attempts task-i >/dev/null
phase_i=$(bash "$STORE" get-phase task-i)
assert_eq "$phase_i" "implement" "(i) incr-attempts does not clobber phase"

# --- summary -------------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit "$FAILURES"
