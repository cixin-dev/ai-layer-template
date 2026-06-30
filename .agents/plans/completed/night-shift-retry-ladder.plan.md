# Plan: Night Shift — decider retry ladder + escalation threshold

## Summary
Extend the pure next-action decider (`scripts/night_shift_decide.sh`, #56) with its
**failure path**: a bounded retry ladder that corrects a bad plan instead of amplifying it,
then escalates. The decider currently treats a `red` gate as an out-of-scope `exit 2` marker;
this slice replaces that marker with the ladder, reading the durable `ATTEMPTS` count
(populated by `loop_state.sh`, #57) and a configurable threshold `MAX_ATTEMPTS` (= K). On a
red gate: attempt 1 → `retry-reimplement`, attempt 2 → `retry-replan`, attempts ≥ K →
`escalate`. The decider stays **pure** (a function of its env-var snapshot — no git/fs, no
side effects); all loop logic remains in it, per ADR-0023 ("schedule, don't judge"). Two test
surfaces land: Seam 1 extends the existing env-driven table tests with every ladder rung +
threshold + idempotency; Seam 2 is a new integration test (`night_shift_retry.test.sh`) where
recorded attempts flow *through* `loop_state.sh` into the decider — proving escalate lands
exactly at K and a restart re-derives the same decision.

## User Story
As a developer, when `/validate` fails, I want the loop to retry along a bounded ladder
(re-implement, then re-plan) rather than re-run the same failing step forever, so that a bad
plan is corrected instead of amplified; and to give up after K attempts and escalate, so a
task that can never pass cannot silently burn tokens all night. (PRD US-8, US-9.)

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | LOW |
| Systems affected | `scripts/` (decider UPDATE + decider test UPDATE + new integration test), `.github/workflows/ci.yml` |
| Issue | #60 |

## Attempt-1 Routing Decision (resolves the issue's open `/plan` call)
The PRD left attempt-1 routing as "**`/retroactive` *or* re-run `/implement`**." **Resolved:
attempt 1 → `retry-reimplement` (re-run `/implement`), NOT `/retroactive`.** The loop never
runs `/retroactive` itself; the `escalate` rung hands the task to a human, who may *then*
choose `/retroactive` in the outer loop. Rationale:

1. **Scope mismatch.** `/retroactive` is the *System Evolution outer loop* — it edits the AI
   Layer (CLAUDE.md, commands, skills) so a *class* of defect can't recur. That is a
   meta-improvement of the harness, not a correction of *this task's* red gate. The retry
   ladder's job is to fix *this task's* artifacts, cheapest-first.
2. **HEAD-race hazard.** `/retroactive` is HEAD-mutating and, per CLAUDE.md's
   `night-shift-checkout-isolation` rule, runs in the **main checkout**. Invoking it
   automatically mid-loop would trigger the exact HEAD race the AI Layer forbids between the
   Night Shift and an interactive HEAD-mutating session. `retry-reimplement` stays inside the
   task's own worktree sandbox — no main-checkout mutation, no race.
3. **Cheapest-correct-first.** A *first* red is most cheaply explained by a flawed
   implementation of a sound plan → re-implement against the existing plan (local, low blast
   radius). Only a *second* red justifies suspecting the plan (→ `retry-replan`).
   `/retroactive` (suspecting the *harness*) sits even higher up the causal chain and belongs
   to the human-run outer loop after the PR, not the inner retry ladder.
4. **Human-gated by design.** `/retroactive` is an explicitly HITL, interactive command;
   folding it into an unattended loop contradicts its design and ADR-0010 (semantic flow
   crosses sessions via human/agent handoff, not a mechanical trigger).

This also confirms and grounds the issue's own "What to build" pre-leaning ("attempt 1 →
re-run the implement step").

## Ladder Semantics (the decision table this slice pins)
`MAX_ATTEMPTS` = K = the escalation threshold; the decider escalates when `ATTEMPTS >= K`.
**K resolved to default `3`** (the high end of the PRD's "2–3"): the two-rung ladder
(reimplement → replan) requires escalation *no earlier than* the 3rd attempt, so both rungs
exist. K=2 would delete the `retry-replan` rung — the PRD's named guard against bad-plan
amplification, "the dominant accepted risk of automating `/plan`." K stays configurable
(`MAX_ATTEMPTS` env, default 3); raising it lengthens the replan span, lowering it to 2
disables replan (operator's deliberate choice).

`ATTEMPTS` = the durable count of reds recorded so far for this task (the executor, #62,
increments it via `loop_state.sh incr-attempts` on each red *before* calling the decider).
Decision on `GATE=red`, in precedence order:

| Condition (red gate) | Decision | Why |
|----------------------|----------|-----|
| `ATTEMPTS >= K` (default 3) | `escalate` | bounded — never re-run a failing step forever |
| `ATTEMPTS <= 1` | `retry-reimplement` | first red → flawed impl of a sound plan; cheapest fix |
| else (`2 .. K-1`) | `retry-replan` | suspect the plan itself; structural bad-plan guard |

Terminal (`PR_OPEN`/`ESCALATED` → `noop`) and `green` (→ `open-pr`) still take precedence
over the red ladder — unchanged from #56. `ATTEMPTS=0` + red (a contract violation — red
implies ≥1 attempt) defensively yields `retry-reimplement`.

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| The proposed red-branch logic (escalate-at-K beats rungs; `<=1`→reimplement; `2..K-1`→replan) yields the correct token for every ladder edge and is idempotent on identical env | **VERIFIED** | Throwaway spike `spike_ladder.sh` ran the proposed branch over 17 cases — all rungs (K=3), default-K escalate at 3, configurable K=2 (replan disabled, escalate at 2) and K=5 (replan spans 2..4), defensive `ATTEMPTS=0`, terminal/green precedence over red, all happy-path edges unchanged, and same-env-twice idempotency → `PASS=17 FAIL=0`. Spike discarded. |
| Escalate landing **exactly at K** = "not before": at `ATTEMPTS=K-1` the decider replans, at `ATTEMPTS=K` it escalates | **VERIFIED** | Same spike: K=3 → attempt 2 `retry-replan`, attempt 3 `escalate`; K=5 → attempt 4 `retry-replan`, attempt 5 `escalate`. |
| Recorded attempts survive a restart and feed the decider unchanged (Seam 2) — a count written by `loop_state.sh incr-attempts` is read back by a *separate* `get-attempts` process and produces the same decision | **VERIFIED (substrate, #57)** | #57's store probe already proved write→separate-process read-back is stable; this slice's Seam 2 test composes that proven read with the decider. Re-confirmed by Task 3's integration test. |
| Replacing the `red) … exit 2` branch breaks exactly one existing assertion (`check_exit 2 … GATE=red`) and no other | **VERIFIED** | `night_shift_decide.test.sh:54` is the only `GATE=red` case; the #56 plan explicitly said "the retry-ladder slice will replace this assertion." Task 2 converts it to ladder rungs. |
| ADR-0023 authorizes this exact behavior (red → ladder; escalate at objective count K, never on a judged verdict) | **VERIFIED** | `docs/adr/0023-...md:49-51`: "A red gate (objective) routes to the retry ladder; escalation fires at an objective attempt count K — never on a *judged* verdict." No new ADR needed; no canonical-doc edit, so no `## 變更說明` required. |
| The decider stays pure (reads only env vars; no git/fs, no session, no notify) after the change | **VERIFIED (by construction)** | The added reads are `ATTEMPTS`/`MAX_ATTEMPTS` env vars with defaults — same shape as the existing six snapshot vars; the red branch only `echo`s a token. No I/O introduced. |

## Patterns to Follow

**The decider's existing red branch — the exact lines to replace** (keep the surrounding
terminal/green/cascade structure intact):
```bash
# SOURCE: scripts/night_shift_decide.sh:35-44
case "$GATE" in
  green)
    echo "open-pr"
    exit 0
    ;;
  red)
    echo "OUT-OF-SCOPE: red gate → retry ladder (issue #56 is happy-path only)" >&2
    exit 2
    ;;
esac
```

**Snapshot-var read with safe default** (mirror for `ATTEMPTS`, `MAX_ATTEMPTS`):
```bash
# SOURCE: scripts/night_shift_decide.sh:21-26
ISSUE_READY="${ISSUE_READY:-0}"
GATE="${GATE:-unrun}"
```

**Env-driven table test helper** (Seam 1 — extend with ladder `check` cases; for red cases
pass `ATTEMPTS`/`MAX_ATTEMPTS` explicitly, since the harness runs `env -i`):
```bash
# SOURCE: scripts/night_shift_decide.test.sh:10-19
check() {
  local expected="$1" desc="$2"
  shift 2
  local output
  output="$(env -i "$@" bash "$DECIDER" 2>/dev/null)"
  if [ "$output" != "$expected" ]; then
    echo "FAIL: $desc (expected '$expected', got '$output')"
    FAILURES=$((FAILURES + 1))
  fi
}
```

**Integration-test harness** (Seam 2 — mktemp state dir + trap + assert_eq + footer; drive
`loop_state.sh` then `night_shift_decide.sh`):
```bash
# SOURCE: scripts/loop_state.test.sh:4-13 (harness) — adapt for two scripts
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d /tmp/nsretrytest.XXXXXX)"; trap 'rm -rf "$WORK"' EXIT
export NIGHT_SHIFT_STATE_DIR="$WORK/state"
FAILURES=0
assert_eq() { [ "$1" = "$2" ] || { echo "FAIL: $3 (want '$2' got '$1')"; FAILURES=$((FAILURES+1)); }; }
```

**Test footer** (every `*.test.sh` ends this way):
```bash
# SOURCE: scripts/night_shift_decide.test.sh:59-64
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
```

**CI registration** (each test named explicitly; no glob):
```yaml
# SOURCE: .github/workflows/ci.yml:24-25
          bash scripts/night_shift_decide.sh   # (existing)
          bash scripts/loop_state.test.sh
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/night_shift_decide.sh` | UPDATE | Replace the red `exit 2` branch with the retry ladder; add `ATTEMPTS`/`MAX_ATTEMPTS` reads; refresh the header doc (failure members now emitted; document the ladder + K). |
| `scripts/night_shift_decide.test.sh` | UPDATE | Convert the `check_exit 2` red boundary into ladder rung cases; add threshold-at-K, configurable-K, defensive `ATTEMPTS=0`, red-vs-terminal precedence, and idempotency cases. |
| `scripts/night_shift_retry.test.sh` | CREATE | Seam 2 integration: record attempts via `loop_state.sh`, read back through a fresh process (= restart), feed the decider; assert escalate lands exactly at K and a restart re-derives the same decision. |
| `.github/workflows/ci.yml` | UPDATE | Register `bash scripts/night_shift_retry.test.sh` so CI gates the new integration test. |

## Tasks
Ordered, atomic, each independently verifiable. Work test-informed (tdd-gate): update the
decider and its tests together, run to green before moving on; never leave the suite red.

### Task 1: Wire the retry ladder into the decider
- File: `scripts/night_shift_decide.sh`
- Action: UPDATE
- Implement:
  - Add two snapshot reads beside the existing six (after line 26):
    `ATTEMPTS="${ATTEMPTS:-0}"` and `MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"`.
  - Replace the `red)` case body (lines 40-43) with the ladder, in this precedence:
    ```bash
    red)
      if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then echo "escalate"; exit 0; fi
      if [ "$ATTEMPTS" -le 1 ]; then echo "retry-reimplement"; exit 0; fi
      echo "retry-replan"; exit 0
      ;;
    ```
  - Update the header comment block (lines 11-15): drop the "unused this slice" note on
    `ATTEMPTS`; add `MAX_ATTEMPTS` (escalation threshold K, default 3); remove the
    "(this slice emits only …)" parenthetical so the documented output set is the full closed
    set; add a one-line note that a red gate routes to the ladder per ADR-0023.
  - Keep everything else (terminal check, green branch, artifact cascade, final `noop`)
    byte-for-byte unchanged. No git/fs reads, no validation beyond defaults (Simplicity first).
- Mirror: `scripts/night_shift_decide.sh:21-26,35-44`
- Validate: `bash scripts/night_shift_decide.test.sh` (after Task 2) → `All tests passed.`;
  manual smokes: `GATE=red ATTEMPTS=1 bash scripts/night_shift_decide.sh` → `retry-reimplement`;
  `GATE=red ATTEMPTS=2 …` → `retry-replan`; `GATE=red ATTEMPTS=3 …` → `escalate`.

### Task 2: Extend the Seam 1 table tests (pure decider)
- File: `scripts/night_shift_decide.test.sh`
- Action: UPDATE
- Implement: **remove** the `check_exit 2 "red gate exits 2 …"` case (line 54) and the now-unused
  `check_exit` helper if nothing else uses it (it won't — confirm and delete to avoid dead code
  *your change* orphaned). Add a "Retry ladder" section of `check` cases (all use `env -i`, so
  pass red-path vars explicitly):
  - `GATE=red ATTEMPTS=1 REPORT_PRESENT=1` → `retry-reimplement` (first red).
  - `GATE=red ATTEMPTS=2 REPORT_PRESENT=1` → `retry-replan` (second red).
  - `GATE=red ATTEMPTS=3 REPORT_PRESENT=1` → `escalate` (default K=3).
  - `GATE=red ATTEMPTS=4 REPORT_PRESENT=1` → `escalate` (overshoot still escalates).
  - **Threshold-exactly-at-K boundary:** `GATE=red ATTEMPTS=2` → `retry-replan` (just below K,
    does NOT escalate) paired with `ATTEMPTS=3` → `escalate` — the "exactly at K" assertion.
  - **Configurable K:** `GATE=red ATTEMPTS=2 MAX_ATTEMPTS=2` → `escalate`;
    `GATE=red ATTEMPTS=4 MAX_ATTEMPTS=5` → `retry-replan`.
  - **Defensive:** `GATE=red ATTEMPTS=0` → `retry-reimplement`.
  - **Precedence (red ladder must lose to terminal):** `GATE=red ATTEMPTS=2 PR_OPEN=1` → `noop`;
    `GATE=red ATTEMPTS=2 ESCALATED=1` → `noop`.
  - **Idempotency:** add an explicit assertion that two runs of the same red+attempts env
    produce identical output (mirror the spike's double-invocation, or a dedicated `check`
    pair).
- Mirror: `scripts/night_shift_decide.test.sh:10-19,36-54`
- Validate: `bash scripts/night_shift_decide.test.sh` → `All tests passed.` (exit 0).

### Task 3: Add the Seam 2 integration test (decider ⨯ recorded attempts)
- File: `scripts/night_shift_retry.test.sh`
- Action: CREATE
- Implement: harness per `loop_state.test.sh` (mktemp `WORK`, `trap` cleanup,
  `export NIGHT_SHIFT_STATE_DIR="$WORK/state"`, `FAILURES`, `assert_eq`, footer + `exit`).
  Resolve `LOOP_STATE="$SCRIPT_DIR/loop_state.sh"` and `DECIDER="$SCRIPT_DIR/night_shift_decide.sh"`.
  Define a helper that closes the seam:
  ```bash
  decide_for_recorded() {                       # task -> decision, attempts read via a fresh process
    local task="$1"
    local n; n="$(bash "$LOOP_STATE" get-attempts "$task")"   # separate process == restart-survival read
    env -i GATE=red REPORT_PRESENT=1 ATTEMPTS="$n" bash "$DECIDER"
  }
  ```
  Cases:
  - Drive the ladder through the real store: `incr-attempts taskA` →1 → `decide_for_recorded`
    = `retry-reimplement`; again →2 = `retry-replan`; again →3 = `escalate` (escalate lands
    exactly at default K=3, fed by recorded counts).
  - **Escalate-not-before:** assert the attempt-2 read above is `retry-replan`, not `escalate`.
  - **Idempotent restart:** call `decide_for_recorded taskA` twice on the *unchanged* recorded
    state (attempts still 3) → both `escalate`, asserted equal — "same recorded state → same
    decision" across a simulated restart.
  - **Namespacing sanity (optional, cheap):** taskB with `incr-attempts` once → its own
    `retry-reimplement`, unaffected by taskA's count.
- Mirror: `scripts/loop_state.test.sh:4-13` (harness), `scripts/loop_state.sh` interface
  (`get-attempts`, `incr-attempts`)
- Validate: `bash scripts/night_shift_retry.test.sh` → `All tests passed.` (exit 0).

### Task 4: Gate the new integration test in CI
- File: `.github/workflows/ci.yml`
- Action: UPDATE
- Implement: append `          bash scripts/night_shift_retry.test.sh` as the final line of the
  `run:` block (after `bash scripts/loop_state.test.sh`), matching indentation.
- Mirror: `.github/workflows/ci.yml:24-25`
- Validate: `grep -n night_shift_retry .github/workflows/ci.yml` shows the line; block scalar
  shape unchanged.

## Validation
- **Seam 1 (primary):** `bash scripts/night_shift_decide.test.sh` → `All tests passed.`, exit 0.
- **Seam 2 (integration):** `bash scripts/night_shift_retry.test.sh` → `All tests passed.`, exit 0.
- **Regression (unchanged store):** `bash scripts/loop_state.test.sh` → `All tests passed.`
- **Syntax:** `bash -n scripts/night_shift_decide.sh scripts/night_shift_retry.test.sh`.
- **Full local CI mirror** (the exact gate that runs on PR):
  ```
  bash scripts/sync.test.sh && bash scripts/unsync.test.sh && \
  bash scripts/validate_gate.test.sh && bash scripts/security_guard.test.sh && \
  bash scripts/piv_check.test.sh && bash scripts/notify.test.sh && \
  bash scripts/night_shift_decide.test.sh && bash scripts/loop_state.test.sh && \
  bash scripts/night_shift_retry.test.sh
  ```
- **PIV gate (session-end Stop hook):** `bash .claude/validate.sh` → `PIV checks passed.`
  (new tests are gated by CI, not `validate.sh`, matching every sibling test).
- **CI wiring:** `grep -n night_shift_retry .github/workflows/ci.yml` returns the new line.
- **Manual smokes:** `GATE=red ATTEMPTS=1 bash scripts/night_shift_decide.sh` → `retry-reimplement`;
  `ATTEMPTS=2` → `retry-replan`; `ATTEMPTS=3` → `escalate`; `GATE=green …` → `open-pr` (happy
  path still intact).

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors (both decider + integration suites green; full CI mirror green)
- [ ] Decider emits `retry-reimplement` on the first red, `retry-replan` on the second red, per the ladder
- [ ] Decider emits `escalate` exactly at attempt count K (default 3, configurable via `MAX_ATTEMPTS`) — never re-running the same failing step forever
- [ ] attempt-1 routing decision (`/retroactive` vs re-`/implement`) resolved and recorded (→ `retry-reimplement`; see decision section)
- [ ] Table-driven tests cover every ladder edge (Seam 1) and the escalation threshold at K (Seam 2)
- [ ] Idempotent-restart test: same recorded state → same decision
- [ ] Still pure — decider reads only its env snapshot; no git/fs, no session, no push, no notify
- [ ] Follows existing patterns (decider script shape, `*.test.sh` harness, explicit CI test list)
- [ ] CI runs the new integration test (`ci.yml` updated)
