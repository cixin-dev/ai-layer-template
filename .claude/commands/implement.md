---
description: Execute an implementation plan with per-task validation loops and an E2E gate
argument-hint: <path/to/plan.md>
---

# Implement

**Plan**: $ARGUMENTS

This is the **Implement** phase of the [PIV Loop](../skills/piv-loop/SKILL.md). Open it in a
**fresh session** — the plan file is your only inheritance from the Plan phase.

**Golden rule**: if validation fails, fix it before moving on. Never accumulate broken
state.

---

## Phase 1 — Load

Read the plan and extract: summary, patterns to mirror, files to change, the ordered task
list, the validation commands, and any ticket id. If the plan is missing, stop and tell the
user to run `/plan` first.

## Phase 2 — Prepare

Check git state.

| State | Action |
|-------|--------|
| Clean, on main | Create a feature branch |
| Dirty, on main | STOP — ask the user to stash or commit first |
| On a feature branch | Use it |

## Phase 3 — Execute

For each task, in order:

1. **Verify assumptions.** Read the target file and its neighbors (what it imports, what
   imports it). Confirm the functions/types/endpoints the plan references actually exist
   and match. If the plan is wrong, adapt — and document the deviation.
2. **Implement.** Follow the mirror reference. Check integration: do imports resolve, do
   callers still work, does data flow correctly across boundaries?
3. **Validate immediately.** Run the project's check command. On failure: read the error,
   fix the root cause, re-run, proceed only when green.
4. **Track progress** with a simple per-task ✅, and record any deviation from the plan
   and why.

Prefer vertical tracer-bullet slices over a horizontal "all tasks at once" pass — see
[`tdd-gate.md`](../skills/tdd-gate/SKILL.md).

## Phase 4 — Validate

Run the full check suite (lint / type-check / tests). All must pass with zero errors.

**Write tests for new code**: every new behavior gets at least one test exercising the
public interface; cover error and edge cases; test across boundaries, not just functions in
isolation.

### End-to-end verification — hard gate

> Do NOT report complete until every E2E step passes.

Re-read the plan's E2E section and run each test as a checklist: start the app, exercise
the new/changed behavior, confirm the outcome matches the plan, fix-and-rerun on failure.
If the plan has no E2E section, do a smoke test of the feature manually. Static checks and
unit tests alone are never sufficient.

## Phase 5 — Report

Write `.agents/reports/{plan-name}-report.md` capturing: tasks completed, validation
results, files changed, deviations from plan (with rationale), and tests written. Then
archive the plan to `.agents/plans/completed/`.

If a ticket id was in the plan metadata, add a comment to the ticket summarizing what
shipped, the branch, file/test counts, and deviations. Do **not** transition the ticket's
status — status transitions belong to Validate / human review, not the implementer
(self-promoting your own work defeats the PIV separation). Leave the status untouched.

## Phase 6 — Output

Report branch, validation results, files changed, deviations, artifact paths, and the next
step (review in a fresh session, then open a PR). If the run surfaced a bug that the AI
Layer should have prevented, flag it for a [retroactive session](retroactive.md).
