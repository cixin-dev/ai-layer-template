---
description: Run the full validation gate (project verify commands + E2E) as its own PIV session
argument-hint: <path/to/plan.md | blank to use current branch>
---

# Validate

This is the **Validate** phase of the [PIV Loop](../skills/piv-loop/SKILL.md). Open it in a
**fresh session** — the only input is either a plan path or the current branch name.

The validate gate `Stop` hook (`validate_gate.py`) enforces a green floor automatically at
every session end. This command is the *deliberate* full pass: it runs the same gate plus
the plan's E2E checklist and serves as the entry to human review and the System Evolution
handoff.

---

## Phase 1 — Resolve the plan

Resolve which plan to validate via a three-tier contract:

| Input | Action |
|-------|--------|
| Plan path given (`$ARGUMENTS`) | Use it directly; read its E2E section |
| Blank | Infer from current branch `feat/{NN}-{slug}`: try `.agents/plans/{slug}.plan.md`, then fall back to `.agents/plans/completed/{slug}.plan.md` (a re-validation after a prior pass) |
| No plan found | Run the mechanical gate only; state "no plan — E2E skipped" |

**Files are the only durable source.** Never infer E2E steps from the conversation — only
from the plan file. If no plan exists, say so explicitly rather than guessing.

## Phase 2 — Run the mechanical gate

Run the project's verify commands as listed in `CLAUDE.md → Verify commands` (or execute
`.claude/validate.sh` directly if present). Report **PASS / FAIL per command**, then an
**Overall** result.

```
[PASS] bash scripts/sync.test.sh
Overall: PASS
```

On any failure: fix the root cause and re-run before proceeding. Do not move to E2E with a
red gate.

## Phase 3 — Run E2E (if a plan was found)

Re-read the plan's `## Validation` section (or equivalent E2E section) and run each step as a checklist. Confirm every outcome
matches the plan. Fix and re-run on failure.

If the plan has no E2E section, do a smoke test of the changed behavior and note "no E2E
section in plan — smoke test only."

## Phase 4 — Report

Write the final result:

```
Gate:  PASS / FAIL
E2E:   PASS / FAIL / SKIPPED (no plan)
Overall: PASS / FAIL
```

- **PASS**: archive the plan to `.agents/plans/completed/{slug}.plan.md` — this is the point
  a plan becomes "completed" (a green gate, not implementation's end). If the plan was already
  resolved from `completed/` (a re-validation), it is already archived — skip the move. Then
  the tree is ready for human review → merge.
- **FAIL**: list every failing check with its error. Fix, re-run, achieve PASS before
  declaring done. Leave the plan in `.agents/plans/` — a failing gate is not "completed".

## Phase 5 — Human review + System Evolution handoff

On PASS, hand to a human reviewer in a fresh session (open the PR, share the branch).

When human review surfaces a **problem** (a bug that reached the codebase, a class of
miss the AI Layer should have caught), the System Evolution outer loop is triggered through
the workflow: end the review by routing to `/retroactive` in a fresh session. Frame it as
surfacing the option — whether to actually run a retroactive stays judgment (severity ×
recurrence). See [system-evolution](../skills/system-evolution/SKILL.md) and ADR-0010.

This mirrors how `/implement` hands off to `/validate`: each phase deterministically names
its successor, so the workflow routes correctly without relying on the agent's memory.
