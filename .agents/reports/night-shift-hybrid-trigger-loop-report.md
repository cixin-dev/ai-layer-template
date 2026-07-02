# Implementation Report — Night Shift hybrid trigger loop (#63)

**Plan:** `.agents/plans/night-shift-hybrid-trigger-loop.plan.md`
**Branch:** `feat/63-night-shift-loop`
**Date:** 2026-07-02

---

## Tasks completed

- ✅ **Task 1: `select` seam** — `_candidates_tsv()`, `_terminal_for()`, `select_issue()` + tests S1–S4
- ✅ **Task 2: `drain`** — event-driven back-to-back dispatch, kill-switch check, executor-failure pass-through + tests D1–D2
- ✅ **Task 3: `loop`** — persistent poll with INT/TERM trap, MAX_POLLS bound, idle sleep + tests L1–L5
- ✅ **Task 4: CI** — `night_shift_loop.test.sh` added to `.github/workflows/ci.yml`
- ✅ **Task 5: ADR-0025** — `docs/adr/0025-night-shift-trigger-label-is-ready-for-agent.md` created
- ✅ **Task 6: Reconcile stale refs** — `night_shift_decide.sh`, `night_shift_run.sh`, `CONTEXT.md`, `piv-ralph-loop.prd.md` updated
- ✅ **Task 7: Live `select` probe** — ran `bash scripts/night_shift_loop.sh select` → returned `63` (real open `ready-for-agent` Issue, not claimed, no open PR)
- ✅ **Task 8: Operator runbook** — `.agents/reports/night-shift-loop-runbook.md` with every GO/stop check grounded against known-good + known-bad

---

## Validation results

| Gate | Result |
|------|--------|
| `bash scripts/night_shift_loop.test.sh` | All tests passed (15 tests: S1–S4, D1–D2, L1–L5) |
| `bash scripts/night_shift_run.test.sh` | All tests passed (regression — no regressions from Task 6) |
| `bash scripts/night_shift_decide.test.sh` | All tests passed (regression) |
| Live `select` probe | Returned `63` (verified real GitHub path) |

---

## Files changed

| File | Action |
|------|--------|
| `scripts/night_shift_loop.sh` | CREATE — outer loop (select/drain/loop subcommands, kill switch, DI vars) |
| `scripts/night_shift_loop.test.sh` | CREATE — 15 offline unit tests (S1–S4, D1–D2, L1–L5) |
| `.github/workflows/ci.yml` | UPDATE — added `bash scripts/night_shift_loop.test.sh` |
| `docs/adr/0025-night-shift-trigger-label-is-ready-for-agent.md` | CREATE — trigger-label decision |
| `scripts/night_shift_decide.sh` | UPDATE — `ready` → `ready-for-agent` in comment |
| `scripts/night_shift_run.sh` | UPDATE — `ready` → `ready-for-agent` in header; `(#63 renames)` → ADR-0025 ref |
| `CONTEXT.md` | UPDATE — Night Shift + Day Shift defs name `ready-for-agent` with ADR-0025 ref |
| `.agents/prds/piv-ralph-loop.prd.md` | ADD to branch — "unsettled" bullet replaced with decided label |
| `.agents/reports/night-shift-loop-runbook.md` | CREATE — operator runbook |

---

## Deviations from plan

**PRD file path:** `.agents/prds/piv-ralph-loop.prd.md` was an untracked file in the main repo (not yet committed on any branch). Copied it into the worktree and committed it as part of this branch so the edit is tracked. The main repo draft will be superseded when this PR merges.

**`docs/` vs `.agents/reports/` for runbook:** Initially wrote runbook to `docs/night-shift-loop-runbook.md` by mistake; corrected to `.agents/reports/night-shift-loop-runbook.md` before committing.

**`NIGHT_SHIFT_MAX_POLLS=0` concurrency-guard probe:** Using `MAX_POLLS=0` in a probe without fake gh/run caused the real executor to be invoked (got an auth error). The concurrency guard itself behaved correctly; the probe was adjusted to use `MAX_POLLS=1` with fake injections for clean verification.

**D2 test design:** Initial test set `FAKE_CLAIMED=62` (pre-claimed), which caused `select_issue` to skip the issue before dispatch. Fixed by making the fake `$BIN/run` write a `claimed-$n` marker on failure and having the fake `$BIN/gh` read it dynamically — accurately reflecting the executor's behavior (it keeps `in-progress` on failure).

---

## Tests written

| Test | Covers |
|------|--------|
| S1 | Lowest-numbered ready issue wins when multiple are ready |
| S2 | `in-progress` candidates are skipped by `select_issue` |
| S3a | `PR_OPEN=1` candidate excluded as terminal |
| S3b | `ESCALATED=1` candidate excluded as terminal |
| S4 | Empty ready set → empty output |
| D1 | Two issues drained back-to-back; `SLEEP` never invoked while work exists |
| D2 | Executor failure (rc 4) → drain returns 0; error logged; issue dispatched exactly once |
| L1 | Empty queue → sleep invoked; exits after `MAX_POLLS` |
| L2 | Dispatch logged before any sleep (event-driven property) |
| L3 | Pre-existing stop file → exits immediately, no dispatch |
| L4 | Mid-run kill switch: sleep writes stop file → loop stops at next check |
| L5 | `CONCURRENCY=2` → non-zero exit + "serial only" message |
