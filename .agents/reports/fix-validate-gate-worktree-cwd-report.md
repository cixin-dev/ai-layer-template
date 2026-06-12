# Implement Report: fix-validate-gate-worktree-cwd

## Branch
`feat/14-validate-gate-worktree-cwd`

## Tasks Completed

| Task | Status | Notes |
|------|--------|-------|
| Task 1: Create failing test harness (`scripts/validate_gate.test.sh`) | ✅ | Tests (a) and (d) failed against old hook; (b)-(j) passed |
| Task 2: Fix the hook (`validate_gate.py`) | ✅ | All 10 tests pass |
| Task 3: Wire test into verify bundle (`.claude/validate.sh`) | ✅ | All three suites green |
| Task 4: Prove sync flow unaffected | ✅ | `sync.test.sh` and `unsync.test.sh` green, no code changes |
| Task 5: Record retroactive output | ✅ | This report |

## Validation Results

```
bash .claude/validate.sh  →  All tests passed. (x3)
bash scripts/sync.test.sh  →  All tests passed.
bash scripts/unsync.test.sh  →  All tests passed.
bash scripts/validate_gate.test.sh  →  All tests passed.
```

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `scripts/validate_gate.test.sh` | CREATED | +155 |
| `.claude/hooks/validate_gate.py` | UPDATED | +20, -4 |
| `.claude/validate.sh` | UPDATED | +1 |

Commits on branch (past main):
1. `44de518` — `docs(plan): add fix-validate-gate-worktree-cwd plan`
2. `f220207` — `fix(hooks): validate_gate resolves session's actual worktree, not CLAUDE_PROJECT_DIR`

## Deviations from Plan

None. The `resolve_tree` helper was added exactly as sketched in the Design section. The `project_dir` fallback path preserves the two existing skip messages verbatim.

## Retroactive Output

**AI Layer dimension changed:** global-machinery hook (`validate_gate.py`).

**Why the floor went vacuous:** `validate_gate.py`'s `CLAUDE_PROJECT_DIR` resolution predates the worktree convention. When `/implement` adopted worktrees, the Stop-hook gate started validating main's unchanged checkout instead of the feature branch — always green, hence vacuous for the exact sessions ADR-0009 built it to gate.

**What changed:** Added `resolve_tree(data)` — a bounded walk-up from the hook payload's `cwd` field to find the nearest `.claude/validate.sh`, stopping at `$HOME`/filesystem root. Falls back to `CLAUDE_PROJECT_DIR` when the walk finds nothing.

**ADR status:** ADR-0009 (intent: enforced floor every session) and ADR-0012 (copy mechanism) remain accurate as written. `CONTEXT.md`'s glossary entry ("runs the project's `.claude/validate.sh`") stays correct — "the project" now resolves to the session's working tree. No new ADR needed; no decision is reversed, only an implementation gap closed.

## Follow-ups

- **Post-merge sync (do not run from worktree):** after the PR merges and main is pulled, run `bash scripts/sync.sh` from the main checkout so `~/.claude/hooks/validate_gate.py` is refreshed (ADR-0012 drift-refresh contract). Running from the worktree would symlink skills/commands to a path that disappears when the worktree is removed.
- **Risk to verify in /validate E2E:** confirm the Stop hook payload's `cwd` reflects the effective working directory inside a worktree session (not just the launch directory). If `cwd` proves static, the fix still works for sessions launched inside the worktree; a follow-up issue would be needed for cd-into-worktree sessions.
