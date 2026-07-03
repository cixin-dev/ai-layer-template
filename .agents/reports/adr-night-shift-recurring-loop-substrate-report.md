# Implementation Report: ADR — Night Shift recurring-loop runtime substrate

**Plan:** `.agents/plans/adr-night-shift-recurring-loop-substrate.plan.md`
**Issue:** #87
**Branch:** `feat/87-adr-recurring-loop-substrate`
**Worktree:** `../ai-layer-template-feat-87-adr-recurring-loop-substrate`
**Type:** Documentation only — no runtime code changed.

## Summary
Recorded the Night Shift **recurring-invocation substrate** (the outer loop shipped in #81,
`scripts/night_shift_loop.sh`) as a new ADR-0026, and closed the three dangling
"deferred / `/plan`-phase" pointers that ADR-0024 §3, the PRD, and CONTEXT.md had left open.

## Tasks completed
| # | Task | Status |
|---|------|--------|
| 1 | Write ADR-0026 (`docs/adr/0026-night-shift-recurring-loop-substrate-shell-drain-poll.md`) | ✅ |
| 2 | Append forward pointer to ADR-0024's Status line (append-only; §3 body untouched) | ✅ |
| 3 | Close the two PRD deferral pointers + add a Further Notes "decided" bullet | ✅ |
| 4 | Reconcile the CONTEXT.md Night Shift glossary pointer → ADR-0026 | ✅ |
| 5 | Full-repo dangling-pointer sweep + gate | ✅ |

## Files changed
| File | Action | Notes |
|------|--------|-------|
| `docs/adr/0026-night-shift-recurring-loop-substrate-shell-drain-poll.md` | CREATE | Primary deliverable. H1 sentence title; Status / Context / Decision (6 grounded points) / Why-alternatives (cron, `/loop`+`/routines`, Workflow engine) / Consequences. |
| `docs/adr/0024-...own-clone.md` | UPDATE | +1 clause on the Status line only. §3 (lines 47-49) byte-identical (verified via `git diff` + `sed`). Append-only honored. |
| `.agents/prds/piv-ralph-loop.prd.md` | UPDATE | 3 forward pointers → ADR-0026 (Trigger-model bullet, Out-of-Scope bullet, new Further Notes bullet). |
| `CONTEXT.md` | UPDATE | Glossary parenthetical now reads "its runtime substrate is ADR-0026's shell drain+poll loop"; rest of the entry unchanged. English only. |

Grounding for the ADR Decision points was read from `scripts/night_shift_loop.sh` (line refs
verified against the real file: `select_issue:60-72`, `drain:87-116`, `loop:118-136`,
`_require_serial:76-81`, `_stopped:83`, DI seams `17-28`).

## Validation results
- **Gate:** `bash .claude/validate.sh` (runs `scripts/piv_check.sh`) → `PIV checks passed.`, **exit 0** (run from the worktree).
- **ADR presence & format:** file exists; H1 sentence title; `## Context` / `## Decision` / `## Why this over the alternatives` / `## Consequences` all present.
- **Content completeness (grep):** cron ×5, `/loop` ×3, Workflow ×4, ADR-0024 ×7, ADR-0023 ×3, serial ×5, "synchronous" ×1, "idle-poll" ×1, "process-exit" ×1 — all AC-required terms present.
- **AC#4 dangling-pointer sweep:** `grep -rniE "runtime substrate.*(/plan|deferr)|deferred to #63" docs/ .agents/prds/ CONTEXT.md` → 3 hits, **zero bare**:
  - `docs/adr/0024:48` — the §3 Decision body (append-only, kept); its **Status line** now carries the ADR-0026 forward pointer.
  - `prd:249` — carries the ADR-0026 pointer on the adjacent line 250.
  - `prd:273` — carries the ADR-0026 pointer on the adjacent line 274.
- **PRD ADR-0026 hits:** 3 (lines 158, 250, 274).
- **CONTEXT.md:** no residual "stays a `/plan` decision".

## Tests written
None — documentation-only change; no runtime surface to unit-test. Verification is the gate
(`validate.sh` exit 0) plus the grep proofs above (structure, content completeness, and the
AC#4 zero-dangling sweep).

## Deviations from plan (with rationale)
1. **Left PRD line 140's `/plan`-phase decision untouched.** The plan's Task 3 validation said
   "the phrase `/plan`-phase decision no longer appears without an adjacent ADR-0026 pointer,"
   but line 140's `/plan`-phase decision is about the **durable per-task loop-state store**
   ("candidates: the Issue itself, a state record alongside the branch, git-native state") — a
   *distinct* open decision that ADR-0026 does **not** resolve. Attaching an ADR-0026 pointer
   there would misattribute. The plan's own AC#4 is correctly scoped to the **substrate** pointer
   (its sweep regex `runtime substrate.*(/plan|deferr)|deferred to #63` does not match line 140),
   so this honors AC#4 while declining the over-broad Task-3 grep wording.
2. **Minor wording placement in the PRD pointers.** Followed the plan's "e.g." pointer text but
   placed the parenthetical before the sentence period ("…decision **(now decided — see
   ADR-0026: shell drain+poll loop)**.") and used an em-dash without a preceding period in the
   Out-of-Scope bullet ("A `/plan`-phase decision **— now recorded in ADR-0026**.") for
   readability. No semantic change.

## Notes
- Implemented as the Night Shift's own `/implement` phase for #87 (confirmed via process tree:
  `night_shift_loop.sh drain → night_shift_run.sh 87 → claude -p /implement`). Strict worktree
  isolation used throughout; the main checkout was never taken off `main` and its HEAD was never
  mutated (HEAD-race Do-not honored).
- The plan remains at `.agents/plans/adr-night-shift-recurring-loop-substrate.plan.md` on the
  branch. `/validate` archives it to `completed/` on a green gate.

## Next step
`/validate .agents/plans/adr-night-shift-recurring-loop-substrate.plan.md` (fresh session) → PR
(with the `## 變更說明` zh summary authored at Validate Phase 5) → human review.
