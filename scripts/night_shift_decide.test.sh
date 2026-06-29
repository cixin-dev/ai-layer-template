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

# Run the decider and assert it exits with $code.
check_exit() {
  local code="$1" desc="$2"
  shift 2
  local actual=0
  env -i "$@" bash "$DECIDER" >/dev/null 2>&1 || actual=$?
  if [ "$actual" != "$code" ]; then
    echo "FAIL: $desc (expected exit $code, got $actual)"
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
# Boundary marker: red gate is out-of-scope this slice → exit 2
# ---------------------------------------------------------------------------
check_exit 2 "red gate exits 2 (deferred retry ladder)"  GATE=red REPORT_PRESENT=1

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
