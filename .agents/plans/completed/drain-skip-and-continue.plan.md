# Plan: drain skip-and-continue (fix head-of-line blocking of higher-numbered ready Issues)

## Summary
`drain()` in `scripts/night_shift_loop.sh` currently ends the **entire** pass the first
time `select_issue` re-returns the Issue it just dispatched (the #82 no-progress guard).
Because `select_issue` always returns the **lowest** grabbable Issue, a single
low-numbered Issue whose claim never sticks re-appears at the head of every pass and
starves all higher-numbered ready Issues (verified: #63 never dispatched while #62 is
stuck). This implements the Issue's **preferred option 1 — skip-and-continue**: track the
Issues already dispatched *this pass*, exclude them from selection, and end the pass only
when no un-dispatched selectable Issue remains. Each Issue is dispatched **at most once per
pass** (preserves the #81 H1 anti-hot-spin bound); `loop()`'s idle sleep stays the
cross-pass backoff for a stuck Issue.

## User Story
As the Night Shift operator, I want one drain pass to work through **every** ready Issue
even when a low-numbered Issue is stuck-unclaimable, so that higher-numbered ready Issues
are not starved until the stuck one advances.

## Metadata
| Field | Value |
|-------|-------|
| Type | BUG_FIX (labeled `enhancement`; fixes a starvation limitation #82 introduced) |
| Complexity | LOW |
| Systems affected | `scripts/night_shift_loop.sh` (`drain`, `select_issue`), `scripts/night_shift_loop.test.sh` |
| Issue | #84 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| Skip-and-continue drains both a stuck low Issue and a higher ready Issue in **one** pass, each dispatched exactly once, and terminates | **VERIFIED** | Spike `/tmp/spike84/` (modified script + the test's fake `gh`/`run`). D4 case `{62 fail-noclaim, 63 ready}` → `run62=1 run63=1`, rc 0, prints `no progress on #62`. |
| The `[exclude]` param is backward-compatible with the `select` subcommand (called with no arg) | **VERIFIED** | Spike: `exclude="${1:-}"` → `case ",," in *",$n,"*` never matches → no exclusion. S1–S4 call `bash "$LOOP" select` (no arg) and are unaffected. |
| The fix does not regress D1 (both succeed), D2 (fail-with-claim), D3 (fail-noclaim) | **VERIFIED** | Spike re-ran all three: D1 `run62=1 run63=1` no "no progress"; D2 `run62=1` no "no progress" (claimed → not selectable); D3 `run62=1` + "no progress on #62". All rc 0. |
| The H1 hot-spin bound (≤1 dispatch per Issue per pass) is preserved | **VERIFIED** | Excluded Issues are never re-selected within a pass; D3 (timeout-guarded) exits 0 with dispatch count 1. |
| No runbook / operator-card describes drain's "end pass on no-progress" behavior that would go stale | **VERIFIED** | `grep -rln "no progress\|hot-spin\|drain pass\|starv" docs/ *.md .claude/` → only `night_shift_loop.sh` + its test. Option 1 needs **no** doc change beyond the `drain()` comment. |
| `select_issue` has no callers besides `drain` (l.95) and the `select` subcommand (l.147) | **VERIFIED** | `grep -rn select_issue scripts/ docs/ *.md` → only those two call sites. |
| The comment-only fallback (option 2) is unnecessary | **VERIFIED** | Option 1 proved practical in bash (spike passes); no fallback taken. |

## Patterns to Follow

Comma-wrapped set-membership test — mirror the existing claim-label skip:
```bash
# SOURCE: scripts/night_shift_loop.sh:64-66
case ",$labels," in
  *",$CLAIM_LABEL,"*) continue ;;
esac
```

Existing no-progress guard being replaced (drain's `last`-based end-the-pass):
```bash
# SOURCE: scripts/night_shift_loop.sh:89,104-107,114
local last=""
...
if [ "$n" = "$last" ]; then
  echo "no progress on #$n (still selectable after dispatch) — ending drain pass to back off" >&2
  return 0
fi
...
last="$n"
```

Command-substitution select + empty-guard already in drain (reuse verbatim for the stuck probe):
```bash
# SOURCE: scripts/night_shift_loop.sh:95-96
n="$(select_issue)"
[ -n "$n" ] || return 0
```

Test slice + fake-bin scenario style to mirror for the new D4 (fail-noclaim fake already exists):
```bash
# SOURCE: scripts/night_shift_loop.test.sh:222-240 (D3) and:79-99 (fake run: FAKE_RUN_FAIL_NOCLAIM_N)
OUT_D3="$(timeout 20 env NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_D3" NIGHT_SHIFT_STATE_DIR="$ST_D3" TIMELINE="$TL_D3" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent')" \
           FAKE_RUN_FAIL_NOCLAIM_N="62" \
           bash "$LOOP" drain 2>&1)" || RC=$?
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/night_shift_loop.sh` | UPDATE | `select_issue` gains optional `[exclude_csv]`; `drain` tracks a per-pass dispatched set + skip-and-continue; rewrite the guard comment |
| `scripts/night_shift_loop.test.sh` | UPDATE | Add D4 regression (stuck-low + ready-high drained both in one pass); D1/D2/D3 unchanged |

## Tasks
Ordered, atomic, each independently verifiable. Run
`bash scripts/night_shift_loop.test.sh` after each.

### Task 1: `select_issue` accepts an optional exclusion set
- File: `scripts/night_shift_loop.sh`
- Action: UPDATE
- Implement: Add `local exclude="${1:-}"` as the first line of `select_issue`. Immediately
  after `[ -z "$n" ] && continue`, add a skip for excluded numbers, mirroring the
  claim-label case:
  ```bash
  case ",$exclude," in
    *",$n,"*) continue ;;
  esac
  ```
  Update the function's doc line to `# select_issue [exclude_csv] — lowest grabbable Issue
  not present in the optional exclude set (comma-list of numbers dispatched this pass).`
- Mirror: `scripts/night_shift_loop.sh:64-66` (claim-label case idiom)
- Validate: `bash scripts/night_shift_loop.test.sh` — S1–S4 still green (subcommand passes no arg → no exclusion).

### Task 2: `drain` skip-and-continue + rewritten guard comment
- File: `scripts/night_shift_loop.sh`
- Action: UPDATE
- Implement: Replace the `last`-based guard with a per-pass dispatched set.
  - Change `local last=""` → `local dispatched=""` (comma-joined Issue numbers dispatched this pass).
  - Select with the exclusion: `n="$(select_issue "$dispatched")"`.
  - Replace the empty-guard + `if [ "$n" = "$last" ]` block with a single end-of-pass block:
    ```bash
    if [ -z "$n" ]; then
      # No selectable Issue remains that we haven't already dispatched this pass —
      # forward progress is exhausted. If one is STILL selectable but was excluded,
      # its claim never stuck (best-effort `_claim` swallowed by `gh … || true`, or
      # the executor died pre-claim); log it as a diagnostic, but do NOT re-dispatch:
      # each Issue is dispatched at most once per pass (preserves the #81 H1 hot-spin
      # bound), and loop()'s idle sleep is the cross-pass backoff that gives the stuck
      # Issue one more try next poll. Skipping it here is what lets higher-numbered
      # ready Issues still drain (#84).
      stuck="$(select_issue)"
      [ -n "$stuck" ] && echo "no progress on #$stuck (still selectable after dispatch) — ending drain pass to back off" >&2
      return 0
    fi
    ```
  - Keep the `echo "dispatch: #$n"` + `"$RUN" "$n"` + rc-logging block unchanged.
  - Replace `last="$n"` with `dispatched="${dispatched:+$dispatched,}$n"`.
  - Delete the old guard comment block (`scripts/night_shift_loop.sh:97-107`) — it is
    superseded by the new comment above and its "bounded poll-interval retry / re-running
    the same Issue's full PIV cycle" wording no longer describes the behavior (acceptance #4).
- Mirror: `scripts/night_shift_loop.sh:95-96` (select + empty guard), `:64-66` (case idiom)
- Validate: `bash scripts/night_shift_loop.test.sh` — D1/D2/D3 green; drain still serial-guarded and stop-file-aware (unchanged code paths).

### Task 3: Add D4 regression — stuck low Issue does not starve a higher ready Issue
- File: `scripts/night_shift_loop.test.sh`
- Action: UPDATE
- Implement: After the D3 block (`scripts/night_shift_loop.test.sh:240`), add a D4 slice.
  Scenario: `FAKE_GH_TSV` = `62`+`63` both `ready-for-agent`, `FAKE_RUN_FAIL_NOCLAIM_N="62"`
  (62 fails to claim, 63 succeeds). Wrap in `timeout 20` (a regression to head-of-line
  blocking would either loop or drop #63). Assert:
  - `RC == 0` (drain exits 0, no hot-spin).
  - `OUT` contains `dispatch: #62` **and** `dispatch: #63` (both reached in one pass).
  - `grep -c '^run 62$'` == `1` (62 dispatched exactly once — not re-dispatched though still selectable).
  - `grep -c '^run 63$'` == `1` (higher Issue reached — the fix; would be `0` pre-fix).
  Follow D3's exact env-var block and `assert_*` helpers.
- Mirror: `scripts/night_shift_loop.test.sh:222-240` (D3), `:187-200` (D1 two-issue drain)
- Validate: `bash scripts/night_shift_loop.test.sh` — prints `All tests passed.`; the D4
  `run63 == 1` assertion is the head-of-line-blocking regression guard.

## Validation
- **Unit / regression (primary):** `bash scripts/night_shift_loop.test.sh` → `All tests passed.`
  (S1–S4, D1–D4, L1–L5, E1–E2). This is the check command; it was run green on the current
  tree before changes (baseline established) and the D4 assertion flips red without the fix
  (a naive drain drops #63 → `run63 == 0`).
- **Gate:** `bash .claude/validate.sh` (runs `piv_check.sh`; PIV-artifact invariants only —
  does not run these unit tests, so the loop test above is the substantive gate for this change).
- **Syntax:** `bash -n scripts/night_shift_loop.sh`.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `bash scripts/night_shift_loop.test.sh` → `All tests passed.` (zero failures)
- [ ] Option 1 (skip-and-continue) implemented — not the option-2 documentation-only fallback
- [ ] One drain pass with `{62 fails-to-claim, 63 ready}` dispatches **both**; #62 dispatched exactly once (D4)
- [ ] A stuck Issue cannot hot-spin within a pass — each selectable Issue dispatched ≤1×/pass (D3 kept, timeout-guarded)
- [ ] `drain()` guard comment no longer overstates the fix (old "bounded poll-interval retry" wording removed)
- [ ] Follows existing patterns (comma-case membership, DI fake-bin test slices)
- [ ] Every external-behavior claim VERIFIED by the `/tmp/spike84/` probe (see Assumptions & Risks)
