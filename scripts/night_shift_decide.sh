#!/usr/bin/env bash
# Pure next-action decider for the Night Shift loop (ADR-0023: schedule, don't judge).
#
# Input: snapshot env vars (all booleans "1"/"0"; GATE is "unrun"/"green"/"red"; ATTEMPTS is int).
#   ISSUE_READY   — Issue carries the `ready-for-agent` label
#   PLAN_PRESENT  — .agents/plans/{name}.plan.md exists
#   REPORT_PRESENT— .agents/reports/{name}-report.md exists
#   GATE          — validate gate verdict
#   PR_OPEN       — a PR is open for the branch
#   ESCALATED     — task already escalated (terminal)
#   ATTEMPTS      — retry count recorded by the executor via loop_state.sh
#   MAX_ATTEMPTS  — escalation threshold K (default 3); at ATTEMPTS >= K the decider escalates
#
# Output: exactly one token on stdout from the closed set:
#   run-plan | run-implement | run-validate | retry-reimplement | retry-replan | escalate | open-pr | noop
#
# Red gate routes to the retry ladder per ADR-0023: attempt 1 → retry-reimplement,
# attempt 2 → retry-replan, attempts >= K → escalate (bounded; never re-runs forever).
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
ATTEMPTS="${ATTEMPTS:-0}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

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
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then echo "escalate"; exit 0; fi
    if [ "$ATTEMPTS" -le 1 ]; then echo "retry-reimplement"; exit 0; fi
    echo "retry-replan"; exit 0
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
