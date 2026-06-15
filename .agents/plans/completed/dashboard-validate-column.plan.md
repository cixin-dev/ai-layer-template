# Plan: feat(dashboard): surface validate verdict in worktree PIV table

## Summary
`/dashboard`'s "Active Worktrees — PIV Progress" section infers the `VALIDATE` phase purely
from file presence — a plan file plus a matching report (`.claude/commands/dashboard.md`
Phase 3, the file-presence table). But a report existing does **not** mean `/validate` ran or
passed, so the dashboard can show `VALIDATE` for work that never cleared the gate. Since #32
(`chore(validate): embed gate/E2E result block in plan-archive commit`) the plan-archive commit
now carries an auditable `Gate / E2E / Overall` block in its body, so the *real* verdict is
readable from the worktree's git log. This adds a **Validate** column to the worktree table that
reads that verdict, leaving the file-presence Phase column untouched.

## User Story
As a developer scanning the dashboard, I want each active worktree's row to show whether
`/validate` actually passed (not just that a report file exists), so a worktree that never
cleared the gate is visibly distinct from one that did.

## Metadata
| Field | Value |
|-------|-------|
| Type | FEATURE |
| Complexity | LOW |
| Systems affected | `.claude/commands/dashboard.md` (doc-only) |
| Issue | N/A |

## Current behavior (exact reference)
Phase 3 resolves the worktree phase from files alone, and Phase 4 renders a four-column table:

```
# SOURCE: .claude/commands/dashboard.md (Phase 3 table)
| Files present in worktree | Phase |
| No `.agents/plans/` or no plan file | PLAN |
| Plan file, no matching report | IMPLEMENT |
| Plan file + matching report | VALIDATE |
```

The #32 archive commit body (verified against real commit `e0a93fc` from PR #33) contains:

```
Validate session result:
Gate:    PASS  (...)
E2E:     PASS  (...)
Overall: PASS
```

## Design
- **Phase 3** gains a "Resolve the Validate verdict" step: read the worktree's archive commit
  via `git -C {worktree-path} log -1 --grep='plan on green gate' --format='%B'` and map its
  `Overall:` line → `✅ PASS` / `❌ FAIL` / `—` (no verdict recorded yet). The Phase column
  (file-presence inference) is unchanged — the new column reports the audited verdict independently.
- **Phase 4** worktree table gains a **Validate** column.
- Frontmatter `description` updated to mention validate verdicts.

The grep recipe was run against `e0a93fc` and confirmed to extract `Overall: PASS`, so the doc
ships a working recipe rather than an assumed one (Verification-led).

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/commands/dashboard.md` | UPDATE | Phase 3 verdict-resolution step + Phase 4 Validate column + description |

## Tasks
### Task 1: Add the Validate-verdict resolution to Phase 3
- File: `.claude/commands/dashboard.md`
- Action: UPDATE — append the verdict-resolution step + mapping table after the Phase 3 phase table.
- Validate: the documented `git log` recipe extracts `Overall:` from a real archive commit.

### Task 2: Add the Validate column to the Phase 4 render
- File: `.claude/commands/dashboard.md`
- Action: UPDATE — add a `Validate` column to the worktree table with `✅ PASS` / `❌ FAIL` / `—`.

### Task 3: Update the frontmatter description
- File: `.claude/commands/dashboard.md`
- Action: UPDATE — note validate verdicts in the description line.

## Validation
```bash
bash .claude/validate.sh   # PIV checks pass
# Recipe probe (Verification-led — external behavior asserted only after running it):
git log -1 --grep='plan on green gate' --format='%B' e0a93fc | grep 'Overall:'
```
End-to-end: run `/dashboard` with an active worktree that has an archived plan commit; confirm the
Validate column shows the audited verdict, distinct from the file-presence Phase column.

## Risks & Assumptions
1. **Archive-commit subject is stable.** The recipe greps `plan on green gate`, the subject `/validate`
   Phase 4 emits. If that wording changes, the recipe must change with it — they live in the same
   harness and should move together.
2. **Verdict window.** After `/validate` archives the plan to `completed/`, the file-presence Phase
   column may fall back to `PLAN` (non-recursive glob); the new Validate column is what carries the
   `✅ PASS` in that window. Documented as a known interaction, not fixed here.

## Acceptance Criteria
- [ ] Phase 3 documents the verdict-resolution recipe and the `Overall:` → column mapping
- [ ] Phase 4 worktree table has a `Validate` column
- [ ] Recipe verified against a real archive commit (not assumed)
- [ ] `bash .claude/validate.sh` green
