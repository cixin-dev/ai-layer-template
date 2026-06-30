# Implementation Report: night-shift-retry-ladder

## Tasks completed
- ✅ Task 1: Wired retry ladder into `scripts/night_shift_decide.sh` — added `ATTEMPTS`/`MAX_ATTEMPTS` snapshot reads; replaced red-gate `exit 2` stub with the bounded ladder; refreshed header doc.
- ✅ Task 2: Extended `scripts/night_shift_decide.test.sh` — removed `check_exit` helper and the `exit 2` boundary case (now dead); added 13 new `check` cases covering all ladder rungs, threshold-exactly-at-K, configurable K, defensive `ATTEMPTS=0`, red-vs-terminal precedence, and idempotency.
- ✅ Task 3: Created `scripts/night_shift_retry.test.sh` — Seam 2 integration test driving `loop_state.sh` → separate-process read → decider; covers escalate-exactly-at-K, escalate-not-before, idempotent-restart, and namespace independence.
- ✅ Task 4: Registered `bash scripts/night_shift_retry.test.sh` in `.github/workflows/ci.yml`.

## Validation results
- `bash scripts/night_shift_decide.test.sh` → `All tests passed.`
- `bash scripts/night_shift_retry.test.sh` → `All tests passed.`
- `bash scripts/loop_state.test.sh` → `All tests passed.` (regression clean)
- Full CI mirror (all 9 test suites) → all passed
- `bash -n scripts/night_shift_decide.sh scripts/night_shift_retry.test.sh` → clean
- `bash .claude/validate.sh` → `PIV checks passed.`
- Manual smokes: `ATTEMPTS=1` → `retry-reimplement`; `ATTEMPTS=2` → `retry-replan`; `ATTEMPTS=3` → `escalate`; `GATE=green` → `open-pr`

## Files changed
| File | Action |
|------|--------|
| `scripts/night_shift_decide.sh` | UPDATED — ladder + `ATTEMPTS`/`MAX_ATTEMPTS` reads + doc |
| `scripts/night_shift_decide.test.sh` | UPDATED — removed `check_exit` helper + exit-2 case; added 13 ladder cases |
| `scripts/night_shift_retry.test.sh` | CREATED — Seam 2 integration test (5 assertions) |
| `.github/workflows/ci.yml` | UPDATED — registered new integration test |

## Deviations from plan
None. All assumptions verified; all task steps followed as specified.

## Tests written
- 13 new `check` cases in `night_shift_decide.test.sh` (Seam 1)
- 5 `assert_eq` cases in `night_shift_retry.test.sh` (Seam 2)
