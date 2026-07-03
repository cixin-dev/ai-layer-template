# Report: drain skip-and-continue (fix head-of-line blocking of ready Issues)

**Plan:** `.agents/plans/drain-skip-and-continue.plan.md`
**Issue:** #84
**Branch:** `feat/84-drain-skip-and-continue`

## Summary
Replaced `drain()`'s `last`-based "end the whole pass on first no-progress" guard
(introduced by #82) with per-pass **skip-and-continue**: `select_issue` gained an optional
exclude set, and `drain` tracks the Issues it has dispatched this pass and excludes them
from selection. A stuck low-numbered Issue (claim never sticks) is now dispatched **once**
per pass, then skipped — so higher-numbered ready Issues still drain instead of being
starved. Each Issue is still dispatched at most once per pass (#81 H1 hot-spin bound
preserved); `loop()`'s idle sleep remains the cross-pass backoff.

## Tasks completed
| Task | Status | Notes |
|------|--------|-------|
| 1 — `select_issue` accepts optional `[exclude_csv]` | ✅ | Added `local exclude="${1:-}"` + comma-wrapped membership skip mirroring the claim-label `case`. |
| 2 — `drain` skip-and-continue + rewritten guard comment | ✅ | `last` → `dispatched`; select with exclusion; end-of-pass block logs the still-selectable stuck Issue as a diagnostic without re-dispatching; old "bounded poll-interval retry" comment removed. |
| 3 — D4 regression (stuck-low + ready-high both drained) | ✅ | Mirrors D3's env block; `timeout 20` guard; asserts both dispatched, 62 once, 63 once. |

## Files changed
| File | Change |
|------|--------|
| `scripts/night_shift_loop.sh` | `select_issue` gains `[exclude_csv]`; `drain` per-pass dispatched set + skip-and-continue; guard comment rewritten. (+21/−13) |
| `scripts/night_shift_loop.test.sh` | Added D4 regression slice after D3. (+25) |

## Tests written
- **D4** — `{62 fails-to-claim, 63 ready}` in one drain pass. Asserts: `RC == 0`;
  output contains `dispatch: #62` **and** `dispatch: #63`; `run 62` logged exactly once
  (H1 bound); `run 63` logged exactly once (the fix — `0` pre-fix). Mirrors D3's
  DI fake-bin scenario style and `assert_*` helpers.

## Validation results
- `bash scripts/night_shift_loop.test.sh` → **`All tests passed.`** (S1–S4, D1–D4, L1–L5, E1–E2).
- `bash -n scripts/night_shift_loop.sh` → syntax OK.
- `bash -n scripts/night_shift_loop.test.sh` → syntax OK.
- **Verification-led (D4 flips for the right reason):**
  - *Known-good* — current tree: green.
  - *Known-bad* — the new test run against the **pre-fix** `drain` (`git show HEAD:scripts/night_shift_loop.sh`,
    confirmed to still contain `local last=` and lack `select_issue "$dispatched"`): D4 fails
    with `missing 'dispatch: #63'` and `run63 want '1' got '0'`, suite `rc=1` (a real assertion
    failure that genuinely executed — not an exec-failure forged flip). This is the exact
    head-of-line-blocking starvation the fix removes.
- `bash .claude/validate.sh` (piv_check) — run after committing implementation + this report.

## Deviations from plan
1. **`select_issue` doc line was added, not updated.** The plan said "update the function's
   doc line," but `select_issue` had no pre-existing comment. Added the specified doc line
   (`# select_issue [exclude_csv] — ...`) above the function. No behavioral impact.
2. **No-progress diagnostic now references the re-probed stuck Issue (`#$stuck`), not the
   loop variable.** After the pass exhausts its un-dispatched set, `drain` re-runs
   `select_issue` (no exclusion) to name any still-selectable Issue for the log line. In D3
   this resolves to `#62`, so the existing `no progress on #62` assertion is unchanged.
   Matches the plan's Task 2 end-of-pass block verbatim.

## Next step
`/validate .agents/plans/drain-skip-and-continue.plan.md` in a fresh session (full gate +
E2E + human review entry), then open a PR. After merge, `/clean-worktree
feat/84-drain-skip-and-continue`.
