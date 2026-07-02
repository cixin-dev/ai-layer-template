# Report: Reconcile "event-driven / concurrency dial" wording with the shipped synchronous serial drain

**Plan**: `.agents/plans/night-shift-wording-reconcile.plan.md`
**Issue**: #86
**Branch**: `feat/86-night-shift-wording-reconcile`
**Type**: BUG_FIX (documentation accuracy) — zero behavior change

## Summary
Corrected canonical-doc prose that oversold the shipped Night Shift outer loop. The docs called
the happy path "event-driven", framed the ~5-min poll as "recovering dropped completion events",
and presented concurrency as a "graduatable dial (1→N) without re-architecting." The shipped loop
(`scripts/night_shift_loop.sh`) is a **synchronous serial busy-drain in one process** plus a
discovery/liveness poll, with the concurrency "dial" being only an enforce-serial (reject-if-≠1)
guard. All edits are prose; no script changed.

## Tasks completed (8/8)
| # | File | Edit | Status |
|---|------|------|--------|
| 1 | PRD | US-19: poll = discovery + liveness (not dropped-event recovery) | ✅ |
| 2 | PRD | US-20: "event-driven happy path" → synchronous zero-idle drain | ✅ |
| 3 | PRD | US-18: concurrency = guarded enforce-serial dial; N flagged unbuilt | ✅ |
| 4 | PRD | "Trigger model = hybrid" decision → synchronous framing | ✅ |
| 5 | PRD | "Concurrency is a dial" decision → guarded/enforce-serial | ✅ |
| 6 | CONTEXT.md | Night Shift entry (260–263) → synchronous drain + discovery/liveness | ✅ |
| 7 | ADR-0023 | line 11 Context noun "event channel" → "synchronous trigger chain" (decision untouched) | ✅ |
| 8 | Runbook | line 93 bare "event-driven" → "zero-idle" (parenthetical kept) | ✅ |

## Files changed (exactly 4, per surgical-diff check)
- `.agents/prds/piv-ralph-loop.prd.md`
- `CONTEXT.md`
- `docs/adr/0023-night-shift-triggers-schedule-not-judge.md`
- `.agents/reports/night-shift-loop-runbook.md`

(Plus the branch-only plan seed + this report + the plan's recorded deviation.)

## Validation results
**Project gate** — `bash .claude/validate.sh` → `PIV checks passed.` (rc=0).

**E2E acceptance sweep** (from the plan's Validation section, run in the worktree):
- Sweep 1 (no bare async-event framing in PRD/CONTEXT/ADRs, excl. ADR-0024) → **empty ✅**
- Sweep 2 (`enforce-serial guard` / `guarded dial` in PRD) → **US-18 + "Concurrency is a guarded dial" decision both hit ✅**
- Sweep 3 (no `dropped completion event` / `recovers dropped` in CONTEXT/PRD) → **empty ✅**
- Sweep 4 (surgical diff) → **exactly the 4 intended files ✅**
- Per-task: `event-driven` in runbook → empty ✅; `event channel` in ADR-0023 → empty ✅
- All three remaining `async event` usages are *negations* ("not an async event" / "there is no async event").

No unit tests apply (docs-only change); verification is the grep sweep + PIV structural gate.

## Deviations from plan (1)
- **Tasks 4 & 6 — `async event channel` → `async event`.** The plan's prescribed replacement text
  for Tasks 4 and 6 used the negating phrase "…no/not an **async event channel**", which still
  contains the literal `event channel` string that the plan's own **Sweep 1** greps for and its
  Acceptance Criteria require to return **empty** — an internal contradiction. Resolved by dropping
  the noun `channel` in both spots, matching the "not an async event" phrasing the plan already
  approved for **US-20 (Task 2)**. Meaning preserved (async mechanism still explicitly denied),
  Sweep 1 now empty, last literal `event channel` removed from canonical docs (more aligned with
  the stated goal). Recorded in the plan under "Implementation deviations". Tasks 1–3, 5, 7, 8
  applied verbatim.

## Context note (for the human reviewer)
This `/implement` ran as the **Night Shift's own headless serial worker** for #86
(`night_shift_loop.sh drain` → `night_shift_run.sh 86` → `claude -p /implement`), not an
out-of-band interactive session. The drain loop is serial (concurrency=1) and was blocked on this
invocation, so no concurrent `main`-HEAD mutator existed; the dormant `feat/84` worktree (PR #90,
awaiting merge) is unrelated. `/implement` isolated its work in
`../ai-layer-template-feat-86-night-shift-wording-reconcile` — no HEAD race.

## Next step
`/validate .agents/plans/night-shift-wording-reconcile.plan.md` in a fresh session (full gate +
E2E + `## 變更說明` PR-body authoring), then open a PR. After merge, `/clean-worktree
feat/86-night-shift-wording-reconcile`.
