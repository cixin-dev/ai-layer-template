# Plan: Night Shift — GC a task's `.state` when its Issue closes

## Summary
The Night Shift per-task loop state (`.night-shift/<N>.state`) is write-only: `loop_state.sh`
has no delete, and on a terminal `noop` the executor drops the `in-progress` claim but leaves
the `.state` file. Once the PR merges and the Issue closes, nothing revisits the task, so the
file lingers forever (observed: `84/86/87.state` for merged Issues). Fix in two surgical pieces:
(1) add a `clear <task>` subcommand to `loop_state.sh` (idempotent `rm -f`), and (2) add a
poll-time GC sweep at the **top of `drain()`** in `night_shift_loop.sh` that, for each
`<N>.state`, reads the Issue state via the injected `$GH` and calls `loop_state.sh clear <N>`
**only when the Issue is `CLOSED`**. Keying on Issue-CLOSED is the same signal the dashboard
already uses; because escalated-but-open and PR-open-but-unmerged tasks keep their Issue OPEN,
they are spared by construction. This makes the state dir honest-by-construction instead of
honest-by-every-reader's-vigilance.

## User Story
As a Night Shift operator I want stale `.state` files to disappear once their Issue closes so
that the state dir reflects only live work and no reader has to remember to ignore dead files.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | LOW |
| Systems affected | Night Shift loop-state store (`loop_state.sh`), outer loop (`night_shift_loop.sh`) + their unit tests |
| Issue | #97 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| `gh issue view <N> --json state --jq .state` prints `CLOSED` for a closed task **Issue**, `OPEN` for open | **VERIFIED** | `gh issue view 84/86/87/63 …` → `CLOSED`; `gh issue view 97 …` → `OPEN`. URLs confirm `/issues/` (real Issues). |
| A nonexistent/unreadable Issue fails safe (no deletion) | **VERIFIED** | `gh issue view 99999999 --json state --jq .state` → stdout empty, `rc=1`. With `2>/dev/null || true` and an **exact** `= "CLOSED"` test, empty ≠ CLOSED → never deletes. |
| `.state` files are keyed by **Issue** number, so GC never sees a PR's `MERGED` state | **VERIFIED** | Task id in state = the `ready-for-agent` Issue the loop dispatches/claims (`night_shift_run.sh:47,105`). Probe artifact: `gh issue view 92` (a PR number) returns `MERGED`; real Issue numbers never do. Delete condition is an **allowlist** `== "CLOSED"`, so even a stray `MERGED` would not delete. |
| The production substrate runs `drain` (not the persistent `loop()`) each poll | **VERIFIED** | Live process tree: `ns-drain-cron.sh` → `flock -n -E 0 … night_shift_loop.sh drain`; `ns-drain-cron.sh` ends with `exec flock … bash scripts/night_shift_loop.sh drain`. ⇒ GC must live in `drain()` or it never runs in prod. |
| Escalated-but-open and PR-open-but-unmerged tasks keep their Issue OPEN (so CLOSED-keyed GC spares them) | **VERIFIED** | `dispatch escalate` only notifies + `set-escalated` (no Issue close, `night_shift_run.sh:182-189`); `noop` only releases the claim label (`:251-256`). Issue closes only when its PR merges. |
| The `*.state` glob excludes the `stop` kill-switch sentinel | **VERIFIED** | `STOP_FILE=$STATE_DIR/stop` (no `.state` suffix, `night_shift_loop.sh:43`); `*.state` cannot match it. |
| Both edited files stay gate-green on exec-bit; CI already runs both test files | **VERIFIED** | `git ls-files -s` → both `100755`; `ci.yml:26,29` run `loop_state.test.sh` + `night_shift_loop.test.sh`. No new `.sh`, no CI edit. |
| Adding GC to `drain()` does not perturb existing drain/loop tests | **VERIFIED (by inspection)** | D1–D4/L1–L4 use freshly-`mkdir`'d, empty `NIGHT_SHIFT_STATE_DIR`s and the fake `run` writes markers to `RUN_STATE`, not `.state` files → GC's `*.state` glob finds nothing → no-op; `select`/`-h`/`loop` paths that don't call `drain` never run GC. |

## Patterns to Follow

Subcommand dispatch + idempotent file op, and the shared `_file` path builder — mirror exactly:
```bash
# SOURCE: scripts/loop_state.sh:8, 32, 56-58
_file() { printf '%s/%s.state' "$STATE_DIR" "$1"; }
...
  set-escalated)
    _write "$(_file "$task")" escalated 1
    ;;
```

The loop's DI'd-external + `STORE` sibling-script pattern to reuse (`$GH`, and how the executor
references `loop_state.sh`):
```bash
# SOURCE: scripts/night_shift_loop.sh:33  and  scripts/night_shift_run.sh:43,105
GH="${NIGHT_SHIFT_GH:-gh}"
STORE="$SCRIPT_DIR/loop_state.sh"          # night_shift_run.sh:43
phase="$(bash "$STORE" get-phase "$n")"    # night_shift_run.sh:105 — how STORE is called
```

`drain()` head — GC hooks in right after the serial guard, before the dispatch `while`:
```bash
# SOURCE: scripts/night_shift_loop.sh:94-97
drain() {
  _require_serial || return $?
  local dispatched=""
  while :; do
```

Loop-test fake `gh` (extend its `case`) and the lettered assert style:
```bash
# SOURCE: scripts/night_shift_loop.test.sh:52-70  (fake gh case)  and  scripts/loop_state.test.sh:13-18 (assert_eq)
case "$1 $2" in
  "issue list") ... ;;
esac
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/loop_state.sh` | UPDATE | Add `clear <task>` subcommand (idempotent `rm -f`) + usage strings |
| `scripts/loop_state.test.sh` | UPDATE | Test `clear` removes an existing file; is a no-op (rc 0) when absent |
| `scripts/night_shift_loop.sh` | UPDATE | Add `STORE` var + `_gc_closed_states` sweep; call it at top of `drain()` |
| `scripts/night_shift_loop.test.sh` | UPDATE | Extend fake `gh` with an `issue view`/`FAKE_CLOSED` case; add Slice G (GC) tests |

## Tasks
Ordered, atomic, each independently verifiable. Work test-first per `.claude/skills/tdd-gate`
(write the assertion, watch it go red for the right reason, then make it green).

### Task 1: `loop_state.sh` — add `clear` subcommand
- File: `scripts/loop_state.sh`
- Action: UPDATE
- Implement:
  - Add a case arm (place after the `set-escalated` arm, `:58`):
    ```bash
    clear)
      rm -f "$(_file "$task")"
      ;;
    ```
    `rm -f` is idempotent — rc 0 whether or not the file exists. `clear` needs a `$task`; the
    existing arg guard (`:27`) already errors (exit 2) when `task` is empty.
  - Add `clear` to both usage strings (`:28` and `:71`), e.g.
    `<get-phase|get-attempts|get-escalated|set-phase|set-escalated|incr-attempts|clear>`.
- Mirror: `scripts/loop_state.sh:56-58` (case arm shape), `:8` (`_file`)
- Validate: `bash scripts/loop_state.test.sh` (still green after Task 2 adds coverage)

### Task 2: `loop_state.test.sh` — cover `clear`
- File: `scripts/loop_state.test.sh`
- Action: UPDATE
- Implement: after case `(n)` (`:117`), add two cases in the same style:
  - `(o)` write a phase, `clear`, assert `get-phase` is empty **and** the on-disk
    `$NIGHT_SHIFT_STATE_DIR/<task>.state` no longer exists.
  - `(p)` capture rc of `clear` on a never-created task; `assert_eq "$rc" "0"` (idempotent no-op).
- Mirror: `scripts/loop_state.test.sh:29-31` (write→read), `:13-18` (`assert_eq`)
- Validate: `bash scripts/loop_state.test.sh` → `All tests passed.` (exit 0).
  TDD check: run it **before** Task 1's impl and confirm it goes red for the right reason
  (`clear` prints `Unknown subcommand: clear`, exit 2), then green after.

### Task 3: `night_shift_loop.sh` — GC sweep in `drain()`
- File: `scripts/night_shift_loop.sh`
- Action: UPDATE
- Implement:
  - Add near the other var defs (after `STOP_FILE=…`, `:43`): `STORE="$SCRIPT_DIR/loop_state.sh"`
    (mirrors `night_shift_run.sh:43`; a sibling script, not an injected external).
  - Add the sweep in the loop-helpers section (near `_stopped`, `:90`):
    ```bash
    # _gc_closed_states — poll-time GC (#97): drop <N>.state for any task whose Issue is
    # CLOSED (the same signal the dashboard uses). Keyed on Issue-CLOSED ONLY: a merged PR
    # closes its Issue, so merge → close → next poll → GC. Escalated-but-open and
    # PR-open-but-unmerged tasks keep their Issue OPEN and so survive (deleting either would
    # re-escalate / re-plan from scratch). The *.state glob excludes the `stop` sentinel by
    # construction. Fail-safe: delete ONLY on an exact CLOSED (allowlist) — a gh error/empty
    # read is treated as "keep" (a lingering file is harmless; an erroneous delete is not).
    _gc_closed_states() {
      local f n state
      for f in "$NIGHT_SHIFT_STATE_DIR"/*.state; do
        [ -e "$f" ] || continue                       # no matches → literal glob → skip
        n="$(basename "$f" .state)"
        case "$n" in ''|*[!0-9]*) continue ;; esac    # only Issue-numbered state files
        state="$("$GH" issue view "$n" --json state --jq .state 2>/dev/null || true)"
        if [ "$state" = "CLOSED" ]; then
          echo "gc: #$n closed — clearing loop state"
          bash "$STORE" clear "$n" || true
        fi
      done
    }
    ```
  - Call it at the top of `drain()`, right after `_require_serial || return $?` and before
    `local dispatched=""` (`:95-96`): a single line `_gc_closed_states`. (Top of `drain` = once
    per poll cycle in both the cron→`drain` substrate and the persistent `loop()`.)
- Mirror: `scripts/night_shift_run.sh:43,105` (`STORE` + `bash "$STORE" …`);
  `scripts/night_shift_loop.sh:47-54` (`$GH` usage), `:90` (helper placement)
- Validate: `bash scripts/night_shift_loop.test.sh` (green after Task 4)

### Task 4: `night_shift_loop.test.sh` — fake `gh issue view` + Slice G (GC)
- File: `scripts/night_shift_loop.test.sh`
- Action: UPDATE
- Implement:
  - Extend the fake `gh` `case` (`:53-70`) with an `issue view` arm driven by a `FAKE_CLOSED`
    space-list (emulates `--jq .state` → prints the raw state string):
    ```bash
      "issue view")
        n="$3"; st="OPEN"
        for c in ${FAKE_CLOSED:-}; do [ "$c" = "$n" ] && st="CLOSED"; done
        printf '%s\n' "$st"
        ;;
    ```
  - Add a **Slice G** after Slice D:
    - `(G1)` — the Issue's required test. Prepopulate `NIGHT_SHIFT_STATE_DIR` with `84.state`
      (→ `FAKE_CLOSED="84"`), `86.state` (escalated-but-open: `phase=validate\nescalated=1`),
      `87.state` (pr-open-but-open: `phase=plan`). Run `bash "$LOOP" drain` with
      `FAKE_GH_TSV=""`. Assert rc 0; `84.state` **gone**; `86.state` and `87.state` **present**;
      output contains `gc: #84`.
    - `(G2)` — stop-sentinel safety. State dir holds only a `stop` file plus `88.state`
      (`FAKE_CLOSED="88"`). Run `drain` (it GC-sweeps *before* the kill-switch short-circuit).
      Assert `stop` **present** (glob never matched it) and `88.state` **gone**.
- Mirror: `scripts/night_shift_loop.test.sh:52-70` (fake gh), `:187-200` (Slice D1 harness &
  env-var invocation), `:17-36` (assert helpers)
- Validate: `bash scripts/night_shift_loop.test.sh` → `All tests passed.` (exit 0)

## Validation
Run from the repo root (or the task worktree):
- `bash scripts/loop_state.test.sh` → `All tests passed.` exit 0
- `bash scripts/night_shift_loop.test.sh` → `All tests passed.` exit 0
- `bash .claude/validate.sh` → exec-bit + PIV gate green (no new `.sh`; both edited files already `100755`)
- Full suite as CI runs it (`.github/workflows/ci.yml`), at minimum the two touched files above.

End-to-end (real `gh`, read-only proof the sweep does the right thing):
- In a scratch state dir, `printf 'phase=validate\n' > /tmp/ns-gc/84.state` then run the sweep
  against real `gh` — Issue #84 is `CLOSED` → file removed; a `printf … > /tmp/ns-gc/97.state`
  for open #97 → file survives. (Grounds the live behavior beyond the injected stub.)

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `loop_state.test.sh` and `night_shift_loop.test.sh` pass with zero failures
- [ ] `.claude/validate.sh` green
- [ ] GC deletes state **only** for `CLOSED` Issues; escalated-but-open, PR-open-but-open, and the `stop` sentinel all survive (asserted by G1/G2)
- [ ] Delete condition is an exact-match allowlist (`== "CLOSED"`), never `!= "OPEN"` — a gh error/empty read never deletes
- [ ] GC lives in `drain()` (runs in the real cron→drain substrate), not only in `loop()`
- [ ] Follows existing patterns (`_file`, `STORE`, DI'd `$GH`, lettered asserts, fake-bin stubs)
- [ ] Every external-behavior claim VERIFIED by a probe (see Assumptions & Risks)
