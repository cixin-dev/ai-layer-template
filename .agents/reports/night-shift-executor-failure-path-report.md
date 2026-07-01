# Implementation Report: night-shift-executor-failure-path

## Tasks Completed

- ✅ Task 1: `loop_state` — durable `escalated` key (`get-escalated` / `set-escalated`)
- ✅ Task 2: `gather_snapshot` — red detection + real `ESCALATED`/`ATTEMPTS` emission
- ✅ Task 3: `_decide` forwards `ATTEMPTS` + `MAX_ATTEMPTS`; `MAX_ITERS` default derived from K
- ✅ Task 4: `dispatch` — `run-plan|retry-replan` unified, `run-implement|retry-reimplement` unified, `escalate` arm added, `NOTIFY` DI var
- ✅ Task 5: `run` loop — increment attempts on red before decide (double-gather), accept `retry-*`/`escalate` tokens
- ⏸ Task 6: Live end-to-end probe — **deferred to operator** (see below)

## Validation Results

All unit suites passed (run inside worktree):
```
bash scripts/loop_state.test.sh          → All tests passed.
bash scripts/night_shift_run.test.sh     → All tests passed.  (Slices A/B/C all green)
bash scripts/night_shift_decide.test.sh  → All tests passed.  (regression guard)
bash scripts/night_shift_retry.test.sh   → All tests passed.  (regression guard)
bash scripts/notify.test.sh              → All tests passed.  (regression guard)
```

PIV gate (`validate.sh`) passes once this report is committed (the only failing check was the missing report file).

No-regression invariants confirmed inside `night_shift_run.test.sh`:
- B5: dispatch performs no `gh`/push/PR of its own ✅
- C3: happy path still reaches `done` in PIV order ✅
- C4: PR-open terminal no-op ✅
- C5: explicit `MAX_ITERS` runaway stop ✅

## Files Changed

| File | Changes |
|------|---------|
| `scripts/loop_state.sh` | Added `get-escalated` / `set-escalated` subcommands; updated usage strings; header comment |
| `scripts/loop_state.test.sh` | Cases (j)–(n): get-escalated unknown→0, set-escalated→1, non-clobber (both directions), restart-survival, missing-key fallback |
| `scripts/night_shift_run.sh` | `NOTIFY` DI var; `MAX_ATTEMPTS_K` constant; `MAX_ITERS` derived from K; `gather_snapshot` reads phase/escalated/attempts + red derivation; `_decide` forwards ATTEMPTS/MAX_ATTEMPTS; `dispatch` unified retry arms + escalate arm; `run` loop increments on red + accepts new tokens |
| `scripts/night_shift_run.test.sh` | A4 description fix; fake notify in BIN; `SIM_FAIL_VALIDATE` in fake claude; new snapshot tests (A-red/A-green-prec/A-esc/A-attempts/A-noesc); new dispatch tests (B-reimpl/B-replan/B-escalate); new drive test (C-fail) with second-run noop assertion |

## Deviations from Plan

None. All patterns followed as specified:
- `_artifact_root` reused for unified retry arms (plan spec §4)
- Notify DI mirrors `validate_gate.py:100-110` pattern
- `incr-attempts` before decide, then double-gather (plan spec §5)
- Non-clobber `_write` preserves sibling keys (existing loop_state invariant)

## Task 6: Live Probe — Deferred to Operator

Task 6 requires subscription credits and physical operator observation. The two ASSUMED claims it would ground:

1. **re-`/implement` resumes & fixes** — the attempt-1 `/implement` re-enters the existing worktree and changes failing code (not a "tasks already done" no-op). **Status: ASSUMED (carry as risk)**
2. **retry-replan propagation** — after attempt-2's `/plan`, the regenerated plan is the one the next `/implement` reads. **Status: ASSUMED (carry as risk)**

To run the live probe:
```bash
# On a throwaway "ready-for-agent" Issue with a deliberately-failing check:
env -u ANTHROPIC_API_KEY bash scripts/night_shift_run.sh <N>
```

Observe: red gate → attempts advance → reimplement → replan → escalation fires once naming phase+attempts → re-run no-ops.

If outcome 2 (replan propagation) fails, file a follow-up issue to pin `/plan`'s re-plan output filename to `{slug}.plan.md`. This is **not blocking** #62's AC (unit tests prove the wiring).

## Tests Written

- `loop_state.test.sh`: 5 new cases (j)–(n)
- `night_shift_run.test.sh`: 5 new snapshot cases, 3 new dispatch cases, 1 new drive case (C-fail) with 11 assertions

## Issue Comment Target

Issue #62 — branch `feat/62-night-shift-executor-failure-path`.
