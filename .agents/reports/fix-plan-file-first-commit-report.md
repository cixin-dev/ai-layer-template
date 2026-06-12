# Implement Report: fix-plan-file-first-commit

## Summary

Docs-only fix: amended `/implement` and `/validate` so the plan file is a tracked first
commit on the branch, visible inside the feature worktree and archived via `git mv` +
commit on green gate.

## Tasks Completed

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Clarify dirty-check row in Phase 2 | ✅ | Split row; carve-out names `.agents/plans/` explicitly |
| 2 | Add "Seed the plan" step to Phase 2 | ✅ | New `### Seed the plan into the branch` section with copy/commit/delete/idempotence steps |
| 3 | Note plan is tracked in Phase 4 | ✅ | Sentence updated; worktree-relative note added; ADR-0013 unchanged |
| 4 | Make `/validate` Phase 1 + Phase 4 worktree-relative | ✅ | Phase 1: sentence added; Phase 4 PASS: `git mv` + commit on branch |
| 5 | Dry-run walkthrough | ✅ | All assertions held — see below |

## Validation Results

```
bash .claude/validate.sh   →  All tests passed. All tests passed.
```

Dry-run assertions (Task 5):
- ✅ Bug reproduced: plan absent in fresh worktree (only `completed/` existed)
- ✅ Seed step: plan visible in worktree after copy+commit
- ✅ Main repo clean after draft deletion
- ✅ `git log main..HEAD` showed exactly one commit: `docs(plan): add demo plan`
- ✅ `git mv` archive commit + squash-merge: `completed/demo.plan.md` survived

## Files Changed

| File | Change |
|------|--------|
| `.claude/commands/implement.md` | +32 / -4 — dirty-check carve-out, Seed section, Phase 4 tracked-file note |
| `.claude/commands/validate.md` | +5 / -4 — Phase 1 worktree-relative sentence, Phase 4 PASS `git mv` + commit |

## Commits on Branch

```
be77811  docs(plan): add fix-plan-file-first-commit plan   ← first commit (plan seed)
b061bac  fix(piv): plan file becomes the branch's first commit
```

## Deviations from Plan

None. All four tasks implemented as specified. Task 5 dry-run matched the plan's
step-by-step prescription exactly.

One meta-point: the seed step was executed manually for this session (since the current
`implement.md` didn't have the step yet), which is exactly what the fix enables for future
sessions. The session served as its own live proof.

## Follow-ups

None required by this change. If reviewer finds the CLAUDE.md Do-not bullet ambiguous
about "leave the plan in `.agents/plans/`" being worktree-relative, a one-line
clarification there is the only candidate scope extension (noted as a Risk in the plan).
