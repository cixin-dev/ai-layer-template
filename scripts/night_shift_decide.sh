#!/usr/bin/env bash
# Pure next-action decider for the Night Shift loop (ADR-0023: schedule, don't judge).
#
# Input: snapshot env vars (all booleans "1"/"0"; GATE is "unrun"/"green"/"red"; ATTEMPTS is int).
#   ISSUE_READY   — Issue carries the `ready` label
#   PLAN_PRESENT  — .agents/plans/{name}.plan.md exists
#   REPORT_PRESENT— .agents/reports/{name}-report.md exists
#   GATE          — validate gate verdict
#   PR_OPEN       — a PR is open for the branch
#   ESCALATED     — task already escalated (terminal)
#   ATTEMPTS      — retry count (unused this slice; consumed by retry-ladder slice)
#
# Output: exactly one token on stdout from the closed set:
#   run-plan | run-implement | run-validate | retry-reimplement | retry-replan | escalate | open-pr | noop
#   (this slice emits only: run-plan | run-implement | run-validate | open-pr | noop)
#
# No side effects: reads no git/fs, spawns no session, pushes nothing, notifies nothing.
# The snapshot is handed to this script by the executor; it does not gather it.
set -euo pipefail

ISSUE_READY="${ISSUE_READY:-0}"
PLAN_PRESENT="${PLAN_PRESENT:-0}"
REPORT_PRESENT="${REPORT_PRESENT:-0}"
GATE="${GATE:-unrun}"
PR_OPEN="${PR_OPEN:-0}"
ESCALATED="${ESCALATED:-0}"

# Terminal states: already done or already escalated.
if [ "$PR_OPEN" = "1" ] || [ "$ESCALATED" = "1" ]; then
  echo "noop"
  exit 0
fi

# Gate verdict.
case "$GATE" in
  green)
    echo "open-pr"
    exit 0
    ;;
  red)
    echo "OUT-OF-SCOPE: red gate → retry ladder (issue #56 is happy-path only)" >&2
    exit 2
    ;;
esac

# Artifact-presence cascade (gate is unrun at this point).
if [ "$REPORT_PRESENT" = "1" ]; then
  echo "run-validate"
  exit 0
fi

if [ "$PLAN_PRESENT" = "1" ]; then
  echo "run-implement"
  exit 0
fi

if [ "$ISSUE_READY" = "1" ]; then
  echo "run-plan"
  exit 0
fi

echo "noop"
