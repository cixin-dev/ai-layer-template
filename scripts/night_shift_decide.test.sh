#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DECIDER="$SCRIPT_DIR/night_shift_decide.sh"

FAILURES=0

# Run the decider with the given env vars and assert stdout equals $expected.
check() {
  local expected="$1" desc="$2"
  shift 2
  local output
  output="$(env -i "$@" bash "$DECIDER" 2>/dev/null)"
  if [ "$output" != "$expected" ]; then
    echo "FAIL: $desc (expected '$expected', got '$output')"
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# Happy-path edges
# ---------------------------------------------------------------------------
check "run-plan"     "ready, no plan → run-plan"        ISSUE_READY=1
check "run-implement" "plan present, no report → run-implement" PLAN_PRESENT=1
check "run-validate" "report present, gate unrun → run-validate" REPORT_PRESENT=1
check "open-pr"      "gate green → open-pr"             GATE=green
check "noop"         "PR open → noop"                   PR_OPEN=1
check "noop"         "escalated → noop"                 ESCALATED=1
check "noop"         "not ready, nothing present → noop"

# ---------------------------------------------------------------------------
# Precedence stress
# ---------------------------------------------------------------------------
check "noop"    "PR-open beats green gate → noop"       PR_OPEN=1 GATE=green
check "open-pr" "green gate beats report present → open-pr" GATE=green REPORT_PRESENT=1
check "run-implement" "ISSUE_READY=0 with plan → run-implement (loop proceeds once started)" ISSUE_READY=0 PLAN_PRESENT=1

# ---------------------------------------------------------------------------
# Retry ladder (red gate)
# ---------------------------------------------------------------------------
check "retry-reimplement" "first red (ATTEMPTS=1) → retry-reimplement"  GATE=red ATTEMPTS=1 REPORT_PRESENT=1
check "retry-replan"      "second red (ATTEMPTS=2) → retry-replan"       GATE=red ATTEMPTS=2 REPORT_PRESENT=1
check "escalate"          "third red (ATTEMPTS=3, default K) → escalate" GATE=red ATTEMPTS=3 REPORT_PRESENT=1
check "escalate"          "overshoot (ATTEMPTS=4) still escalates"       GATE=red ATTEMPTS=4 REPORT_PRESENT=1

# Threshold exactly at K boundary
check "retry-replan" "ATTEMPTS=2 < K=3 → retry-replan (not yet escalate)" GATE=red ATTEMPTS=2 REPORT_PRESENT=1
check "escalate"     "ATTEMPTS=3 = K=3 → escalate (exactly at K)"         GATE=red ATTEMPTS=3 REPORT_PRESENT=1

# Configurable K
check "escalate"          "K=2: ATTEMPTS=2 >= K → escalate"                  GATE=red ATTEMPTS=2 MAX_ATTEMPTS=2 REPORT_PRESENT=1
check "retry-replan"      "K=5: ATTEMPTS=4 < K → retry-replan"               GATE=red ATTEMPTS=4 MAX_ATTEMPTS=5 REPORT_PRESENT=1

# Defensive: ATTEMPTS=0 (contract violation, red implies >= 1 attempt) → retry-reimplement
check "retry-reimplement" "defensive ATTEMPTS=0 → retry-reimplement"          GATE=red ATTEMPTS=0 REPORT_PRESENT=1

# Precedence: red ladder loses to terminal states
check "noop" "PR_OPEN beats red ladder → noop"       GATE=red ATTEMPTS=2 PR_OPEN=1
check "noop" "ESCALATED beats red ladder → noop"     GATE=red ATTEMPTS=2 ESCALATED=1

# Idempotency: same env twice → same output
out1="$(env -i GATE=red ATTEMPTS=2 REPORT_PRESENT=1 bash "$DECIDER" 2>/dev/null)"
out2="$(env -i GATE=red ATTEMPTS=2 REPORT_PRESENT=1 bash "$DECIDER" 2>/dev/null)"
if [ "$out1" != "$out2" ]; then
  echo "FAIL: idempotency: two runs of same red+attempts env differ ('$out1' vs '$out2')"
  FAILURES=$((FAILURES + 1))
fi

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
