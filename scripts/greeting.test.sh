#!/usr/bin/env bash
# Deterministic test for the throwaway greeting probe (Issue #73). Drives the
# helper directly with fixed args — no external state — so it is self-contained.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GREETING="$SCRIPT_DIR/greeting.sh"

FAILURES=0

# check <expected-output> <description> [name-arg...]
check() {
  local expected="$1" desc="$2"
  shift 2
  local output
  output="$(bash "$GREETING" "$@")"
  if [ "$output" != "$expected" ]; then
    echo "FAIL: $desc (expected '$expected', got '$output')"
    FAILURES=$((FAILURES + 1))
  fi
}

check "Hello, world!" "defaults to world when no name given"
check "Hello, Night Shift!" "greets the first-arg name" "Night Shift"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
