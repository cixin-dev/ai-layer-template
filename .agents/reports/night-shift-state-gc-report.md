# Report: Night Shift — GC a task's `.state` when its Issue closes (#97)

## Outcome
Implemented per plan `.agents/plans/night-shift-state-gc.plan.md`. The Night Shift
per-task loop state (`.night-shift/<N>.state`) is now honest-by-construction: a
poll-time GC sweep at the top of `drain()` clears the state file for any task whose
**Issue is CLOSED**, so a merged PR (→ Issue close → next poll) reaps its own state.
Escalated-but-open and PR-open-but-unmerged tasks keep their Issue OPEN and survive.

## Tasks completed
| # | Task | Status |
|---|------|--------|
| 1 | `loop_state.sh` — add `clear <task>` subcommand (idempotent `rm -f`) + usage strings | ✅ |
| 2 | `loop_state.test.sh` — cover `clear` (removes file; idempotent no-op rc 0) | ✅ |
| 3 | `night_shift_loop.sh` — `STORE` var + `_gc_closed_states` sweep, called at top of `drain()` | ✅ |
| 4 | `night_shift_loop.test.sh` — fake `gh issue view` arm + Slice G (G1/G2) | ✅ |

Worked test-first (tdd-gate): for each slice the assertion was added and watched go
red **for the right reason** before the implementation made it green.
- Task 2 red: `Unknown subcommand: clear` (exit 2) → green after Task 1.
- Task 4 red: 3 failures — `(G1) #84 state cleared`, `(G1) GC logged`, `(G2) #88 cleared`
  (GC absent) → green after Task 3.

## Files changed
| File | Change |
|------|--------|
| `scripts/loop_state.sh` | Added `clear)` case arm (`rm -f "$(_file "$task")"`); added `clear` to both usage strings |
| `scripts/loop_state.test.sh` | Added cases `(o)` (clear removes file + get-phase empty) and `(p)` (clear absent task → rc 0) |
| `scripts/night_shift_loop.sh` | Added `STORE="$SCRIPT_DIR/loop_state.sh"`; added `_gc_closed_states` helper (CLOSED-only allowlist, fail-safe on gh error/empty); call at top of `drain()` |
| `scripts/night_shift_loop.test.sh` | Added `"issue view")` arm to fake `gh` (driven by `FAKE_CLOSED`); added Slice G (G1 CLOSED-clears/OPEN-survives, G2 stop-sentinel safety) |
| `.agents/plans/night-shift-state-gc.plan.md` | Seeded as the branch's first commit (Phase 2) |

## Validation results
- `bash scripts/loop_state.test.sh` → `All tests passed.` (exit 0)
- `bash scripts/night_shift_loop.test.sh` → `All tests passed.` (exit 0)
- `bash .claude/validate.sh` → exec-bit check passed; PIV checks passed (green)
- **E2E (real `gh`, read-only sweep):** scratch state dir with `84.state` + `97.state`
  plus a `stop` sentinel (short-circuits `drain` right after the sweep — no dispatch).
  Real `gh issue view`: `#84 → CLOSED`, `#97 → OPEN`. Sweep output `gc: #84 closed —
  clearing loop state` then `kill switch … stopping`. Result: `84.state` removed,
  `97.state` survives. Grounds the live behavior beyond the injected stub, with a
  known-good (delete) + known-keep pair that flips for the right reason.

## Deviations from plan (with rationale)
1. **Worktree base — `origin/main`, then rebased onto local `main`.** Local `main`
   (9c56f81) was one commit behind `origin/main` (c3f77d7, an unrelated security-guard
   doc change #95 that does not touch any of the four target files). I initially based
   the worktree on `origin/main` to avoid a stale PR base. That broke `piv_check.sh`
   Check 1: it resolves the base ref as **local** `main` (`piv_check.sh:53`), so
   `main..HEAD` picked up the inherited #95 commit as the "first commit" (not the plan),
   failing "first commit on branch does not add a plan file." Corrected by rebasing the
   branch onto local `main` (`git rebase --onto main c3f77d7`) — plan+code replay cleanly
   onto 9c56f81 (plan is a new file; the scripts are byte-identical between 9c56f81 and
   c3f77d7). Net: branch based on local `main` per the `/implement` convention;
   ROOT/`main` was never mutated. The squash-merge PR (base = `origin/main`) carries the
   changes regardless of the missing #95 doc commit.
2. **Committed the implementation code + report on the branch.** The `/implement`
   command is implicit about this, but `/validate` only `git mv`s the plan archive and
   pushes — it does not `git add -A` — so the implementation must be committed by
   `/implement` or the PR would omit it (Phase 4: "changes … committed on the branch
   like any other change").

No deviation was needed on the substance of the four tasks — every plan line reference
matched the real files, and the mirror patterns (`_file`, `STORE`, DI'd `$GH`, lettered
asserts, fake-bin stubs) were followed exactly.

## Tests written
- `loop_state.test.sh` `(o)`, `(p)` — `clear` removes the on-disk `.state` and is an
  idempotent rc-0 no-op on an absent task.
- `night_shift_loop.test.sh` Slice G `(G1)`, `(G2)` — the Issue's required behavior:
  CLOSED-Issue state is swept, escalated-but-open / PR-open-but-open state survives, and
  the `stop` kill-switch sentinel is never matched by the `*.state` glob (swept before
  the kill-switch short-circuit).
- Fake-`gh` `issue view` arm (driven by `FAKE_CLOSED`) so the whole GC path tests offline
  with zero credit spend, matching the existing DI'd-external convention.

## Execution context (non-standard)
This `/implement` ran as the **Night Shift's own dispatched implement step** for #97
(process ancestry: `claude ← night_shift_run.sh 97 ← night_shift_loop.sh drain ← cron`),
inside the dedicated Night Shift clone. The drain is a synchronous serial loop
(ADR-0026) currently blocked on this task, so there is no concurrent HEAD-mutator — the
HEAD race is resolved by clone isolation, not by quiescing a shared checkout.

## Next step
`/validate .agents/plans/night-shift-state-gc.plan.md` in a fresh session (full gate +
E2E + human review entry), then open the PR.
