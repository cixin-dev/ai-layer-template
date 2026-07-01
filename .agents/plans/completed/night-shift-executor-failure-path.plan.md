# Plan: Night Shift executor — failure path (retry ladder + escalation + terminal no-op)

## Summary
Wire the thin executor (`scripts/night_shift_run.sh`, #61) to the **failure path**. The pure
decider (#60) already emits `retry-reimplement | retry-replan | escalate | noop`; the executor
just doesn't feed it `ATTEMPTS`/`ESCALATED` and has no dispatch arms for those decisions. This
slice closes that gap: (1) **detect a red gate** — on disk a failed `/validate` is
indistinguishable from "validate never ran" (both leave the plan un-archived), so we derive
`GATE=red` from the **recorded phase** (`loop_state get-phase == validate` + report present +
not archived + not escalated); (2) **advance the attempt counter** once per red gate, *before*
the decider reads it (`loop_state incr-attempts`); (3) **persist escalated** durably via a new
`loop_state` key so a re-run is a true no-op; (4) **dispatch** `retry-reimplement`/`retry-replan`
(re-running `/implement`/`/plan` against the branch's plan in the worktree — the happy-path ROOT
draft is deleted after the first implement) and `escalate` (fire exactly one `notify.sh fail`
naming the failed phase + attempt count, then set the marker); (5) **raise MAX_ITERS** so the
ladder can reach escalate before the runaway cap. The decider is unchanged; all new logic is
deterministic and unit-tested offline with the existing DI'd fakes.

## User Story
As a developer running the Night Shift, I want a red gate to drive a bounded retry ladder that
escalates exactly once after K attempts and then stops touching the task, so that a genuinely
stuck task pages me with the phase + attempt count and never re-opens or duplicates work.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | HIGH |
| Systems affected | `scripts/night_shift_run.sh`, `scripts/loop_state.sh`, executor + loop-state test suites |
| Issue | #62 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| The decider (#60) already returns the full ladder from `ATTEMPTS`/`MAX_ATTEMPTS`/`ESCALATED`; the executor need not change it. | **VERIFIED** | Probe: `for a in 0 1 2 3 4; do env -i GATE=red REPORT_PRESENT=1 ATTEMPTS=$a bash scripts/night_shift_decide.sh; done` → `retry-reimplement, retry-reimplement, retry-replan, escalate, escalate`. `env -i MAX_ATTEMPTS=2 ATTEMPTS=2 …` → `escalate`. `env -i ESCALATED=1 GATE=red ATTEMPTS=9 …` → `noop`; `env -i PR_OPEN=1 …` → `noop`. Also `scripts/night_shift_decide.test.sh:42-60`, `scripts/night_shift_retry.test.sh`. |
| A failed `/validate` is **on-disk identical** to "validate never ran" (plan stays in `.agents/plans/`, report present, no `completed/`, no PR) — filesystem alone cannot detect red. | **VERIFIED** | `.claude/commands/validate.md:89-90` (FAIL: "Leave the plan in `.agents/plans/`"); `.claude/hooks/validate_gate.py` writes **no** durable marker (only a best-effort FAIL notify). So the executor must derive red from something other than files. |
| Recorded phase disambiguates it: `get-phase == validate` **and** not-green ⟹ the validate ran and did not pass ⟹ **red**. | **VERIFIED** | Probe drove real `scripts/loop_state.sh`: phase unset + report + no-completed → `unrun`; after `set-phase validate` (same on-disk) → `red`; with `completed/` present → `green` (green precedence). Safe because `dispatch` blocks on the phase session and records `set-phase validate` only *after* `/validate` returns (`night_shift_run.sh:157-158`), so an observed `phase=validate` means validate has completed. |
| The attempt counter must be incremented **on each red, before the decider reads it** (so the decider sees the post-increment count). | **VERIFIED (spec) + design** | `.agents/plans/completed/night-shift-retry-ladder.plan.md:67-68`: "The executor, #62, increments it via `loop_state.sh incr-attempts` on each red *before* calling the decider." Matches `night_shift_retry.test.sh` order (`incr-attempts` then `decide`). |
| `loop_state.sh`'s `_write`/`_read_key` are generic key/value and preserve sibling keys, so a new `escalated` key coexists with `phase`/`attempts`. | **VERIFIED** | `scripts/loop_state.sh:15-22` (`_write` keeps other keys); `scripts/loop_state.test.sh:76-84` (test (i): `set-phase` doesn't clobber `attempts`, `incr-attempts` doesn't clobber `phase`). Probe confirmed `get-escalated` is **not** yet a subcommand (exit 2), so this slice adds it. |
| The escalate fire is `notify.sh fail` — bell + push, "stuck/needs-human" severity — and its call site is this executor slice. | **VERIFIED** | #58's own plan `.agents/plans/night-shift-notification-two-fires.plan.md:36`: "escalate fire = `notify.sh fail` … The escalate *call site* is a future executor slice (`scripts/night_shift_run.sh`)"; example `:121` `bash "$HOOK" fail "Escalation" "task stuck after K"`. Mirror the DI convention `validate_gate.py:100-110` (`VALIDATE_GATE_NOTIFY` → co-located `notify.sh`, called `notify.sh fail "<Title>" "<repo>: <first_line>"`). |
| Re-invoking `/implement` on an existing branch/worktree (plan already the branch's first commit) **resumes** and can fix a failing gate, rather than no-op'ing "tasks done". | **ASSUMED** | `.claude/commands/implement.md:47-53` ("Worktree already exists → Use that directory"), `:80-83` (plan idempotence guard), `:97-99` ("Validate immediately … fix the root cause") make it *coherent*, but real re-run behavior is a live-session claim. **De-risk:** the executor only owns the *wiring* (invoke `/implement` in the right cwd with the branch plan path — asserted by unit tests); the live probe (Task 6, #61 Seam-3 style) drives a deliberately-failing task through one real retry. |
| Re-invoking `/plan` in the worktree regenerates a plan the subsequent `/implement` picks up (propagates to the branch). | **ASSUMED (carry as risk)** | `/plan` names its output `{kebab-name}.plan.md` from the feature, which may differ from `{slug}`, orphaning the new plan; and a *ROOT* re-plan definitely orphans (implement's guard `implement.md:80-83` surfaces a divergence → the autonomous session stalls). **Mitigation:** dispatch `/plan` in the **worktree** (`_artifact_root`), the strictly-better cwd (new draft lands where the next `/implement` reads). Unit test asserts only the deterministic wiring (`/plan {N}` in the worktree cwd). Real propagation is validated by the live probe (Task 6) and flagged for a possible follow-up to pin `/plan`'s re-plan output name. **Not blocking** #62's AC, which is "re-runs plan (attempt 2)". |
| `claude -p "/validate"` process exit code is **not** a reliable red signal. | **VERIFIED (by avoidance)** | The design never reads the phase-session exit code for the gate verdict — red is derived from recorded phase + `completed/` absence. No claim on `claude -p` exit semantics is made or relied upon. |
| Raising the `MAX_ITERS` **default** does not break existing tests. | **VERIFIED (analysis)** | Worst-case ladder to escalate at K=3 is 10 iterations (plan, implement, validate, [red→reimpl, validate]×, [red→replan, implement, validate], red→escalate, noop). `night_shift_run.test.sh` C5 passes `NIGHT_SHIFT_MAX_ITERS=3` **explicitly** (unaffected by default); C3 happy-path (~5 iters) completes under any default ≥6. New default derives from K: `3*K+6` (=15 at K=3) — generous headroom, still catches true non-advancing runaways. |

## Patterns to Follow

**Dispatch cwd/plan-path resolution** — the failure-path arms reuse exactly what `run-validate`
already does (worktree once it exists, else ROOT; archived plan preferred). `retry-*` unify with
the happy-path arms through `_artifact_root`, which returns ROOT before a worktree exists (first
plan/implement) and the worktree after (retries):
```bash
# SOURCE: scripts/night_shift_run.sh:153-165
run-validate)
  dir="$(_artifact_root "$branch")"
  pp="$(_plan_path_in "$dir" "$slug")"
  claude_run "$dir" "/validate ${pp}"
  bash "$STORE" set-phase "$n" validate
  ;;
```

**Best-effort notify with DI'd command** — mirror the validate gate's escalate-adjacent call:
```python
# SOURCE: .claude/hooks/validate_gate.py:100-110
notify = os.environ.get("VALIDATE_GATE_NOTIFY", str(Path(__file__).resolve().parent / "notify.sh"))
subprocess.run([notify, "fail", "Validate FAIL", f"{repo}: {first_line}"], ... )  # guarded; best-effort
```

**loop_state subcommand — int/bool normalization + generic non-clobber write**:
```bash
# SOURCE: scripts/loop_state.sh:36-43 (get-attempts) and :52-61 (incr-attempts)
get-attempts)
  raw=$(_read_key "$(_file "$task")" attempts)
  if printf '%s' "$raw" | grep -qE '^[0-9]+$'; then printf '%s\n' "$raw"; else printf '0\n'; fi
  ;;
```

**loop_state test style** — `assert_eq`, `mktemp` state dir, exported `NIGHT_SHIFT_STATE_DIR`,
one behavior per case, restart-survival + non-clobber cases:
```bash
# SOURCE: scripts/loop_state.test.sh:76-84 (non-clobber)
bash "$STORE" incr-attempts task-i >/dev/null
bash "$STORE" set-phase task-i implement
assert_eq "$(bash "$STORE" get-attempts task-i)" "2" "(i) set-phase does not clobber attempts"
```

**Executor test fakes** — DI'd `claude`/`gh` logging cwd+args, `SIM_MODE` simulating each phase's
durable-artifact effect so the *next* snapshot advances the decider (proves the executor carries
no loop logic). The failure test adds a red variant of the `SIM_MODE` claude fake:
```bash
# SOURCE: scripts/night_shift_run.test.sh:95-119 (SIM_MODE claude fake — /validate writes completed/ + pr-open)
*"/validate "*)
  mkdir -p "$SIM_ROOT/.agents/plans/completed"
  mv "$SIM_ROOT/.agents/plans/$SIM_SLUG.plan.md" "$SIM_ROOT/.agents/plans/completed/$SIM_SLUG.plan.md" 2>/dev/null || : > ...
  : > "$SIM_STATE/pr-open" ;;
```

**Snapshot faithfulness tests** — already assert `report present + not archived ⇒ GATE=unrun`
(A6) and `completed/ ⇒ GATE=green` (A7). Red-detection extends this without breaking them (A6
has no recorded `phase=validate`, so it stays `unrun`):
```bash
# SOURCE: scripts/night_shift_run.test.sh:168-178 (A6)
assert_eq "$(field "$snap" GATE)" "unrun" "(A6) report present but not archived → GATE=unrun"
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/loop_state.sh` | UPDATE | Add `get-escalated` (→ `0`/`1`, default `0`) + `set-escalated` (writes `escalated=1`) subcommands; extend usage strings. |
| `scripts/loop_state.test.sh` | UPDATE | Tests: `get-escalated` unknown→0, `set-escalated`→1, non-clobber vs `phase`/`attempts`, restart-survival. |
| `scripts/night_shift_run.sh` | UPDATE | (a) `gather_snapshot`: derive `GATE=red` from recorded phase; emit real `ESCALATED` + `ATTEMPTS`. (b) `_decide`: forward `ATTEMPTS` + `MAX_ATTEMPTS`; add `MAX_ATTEMPTS_K` constant. (c) `NOTIFY` DI var. (d) `dispatch`: unify `run-plan\|retry-replan` and `run-implement\|retry-reimplement` via `_artifact_root`; add `escalate` arm. (e) `run` loop: increment on red before decide; accept new decision tokens; derive `MAX_ITERS` default from K. |
| `scripts/night_shift_run.test.sh` | UPDATE | New snapshot (red / escalated / attempts) + dispatch (retry-reimplement / retry-replan / escalate) + full failure-drive tests; fix A4's stale "hard-wired 0" description. |

**No change**: `scripts/night_shift_decide.sh` (ladder already complete, #60); `.github/workflows/ci.yml`
(both test files already wired, `ci.yml:25-26`); `.claude/validate.sh` / `piv_check.sh` (gate is PIV
invariants, not unit tests — run the `*.test.sh` explicitly, see Validation).

## Tasks
Ordered, atomic, each independently verifiable. TDD: write the failing test(s), then the code.

### Task 1: `loop_state` — durable `escalated` key
- File: `scripts/loop_state.sh` (+ `scripts/loop_state.test.sh`)
- Action: UPDATE
- Implement:
  1. In `loop_state.test.sh`, add cases (mirror the `(a)`–`(i)` style): `get-escalated` on an
     unknown task → `0`; after `set-escalated` → `1`; `set-escalated` preserves `phase` and
     `attempts` (non-clobber, both directions); restart-survival (fresh invocation reads `1`).
     Run → the new cases FAIL (subcommands absent).
  2. In `loop_state.sh`: add `set-escalated)` → `_write "$(_file "$task")" escalated 1`; add
     `get-escalated)` → read `escalated`, print `1` iff the value is exactly `1`, else `0`
     (normalize like `get-attempts`). Extend both usage strings to list the new subcommands.
- Mirror: `scripts/loop_state.sh:36-43,44-61` (get/set shape); `scripts/loop_state.test.sh:76-84` (non-clobber).
- Validate: `bash scripts/loop_state.test.sh` → `All tests passed.`

### Task 2: `gather_snapshot` — red detection + real `ESCALATED`/`ATTEMPTS`
- File: `scripts/night_shift_run.sh` (+ `scripts/night_shift_run.test.sh`)
- Action: UPDATE
- Implement:
  1. Tests first, in `night_shift_run.test.sh` (Slice A): (A-red) `set-phase validate` + report present + no `completed/` + no escalation → `GATE=red`; (A-green-prec) `completed/` present + `phase=validate` → `GATE=green`; (A-esc) `set-escalated` + `phase=validate` + report → `GATE` **not** red (stays `unrun`) and `ESCALATED=1`; (A-attempts) `incr-attempts`×2 → snapshot `ATTEMPTS=2`; (A-noesc) fresh task → `ESCALATED=0`. Also fix A4's assertion **description** from "ESCALATED hard-wired 0" to "no escalation marker → ESCALATED=0" (value unchanged). These use `NIGHT_SHIFT_STATE_DIR` pointed at a temp dir so the fake `loop_state` reads/writes are isolated. Run → the red/escalated/attempts cases FAIL.
  2. In `gather_snapshot`: read `phase="$(bash "$STORE" get-phase "$n")"`, `escalated="$(bash "$STORE" get-escalated "$n")"`, `attempts="$(bash "$STORE" get-attempts "$n")"`. Derive GATE: `completed/` present → `green`; else if `phase == validate` **and** `report_present == 1` **and** `escalated != 1` → `red`; else `unrun`. Emit real `ESCALATED=$escalated` (replacing the hard-wired `0` at `:117`) and a new `ATTEMPTS=$attempts` line.
- Mirror: `scripts/night_shift_run.sh:94-118` (gather); the red-derivation prototype verified in planning.
- Validate: `bash scripts/night_shift_run.test.sh` → Slice A green (A6/A7/A8/A9 still pass).

### Task 3: `_decide` forwards `ATTEMPTS` + `MAX_ATTEMPTS`
- File: `scripts/night_shift_run.sh`
- Action: UPDATE
- Implement: add a constant near `MAX_ITERS`: `MAX_ATTEMPTS_K="${NIGHT_SHIFT_MAX_ATTEMPTS:-3}"`
  (comment: mirrors the decider's default K; executor is the source of truth when driving). In
  `_decide`'s `env -i` block, add `ATTEMPTS="$(_field "$snap" ATTEMPTS)"` and
  `MAX_ATTEMPTS="$MAX_ATTEMPTS_K"`. (No behavior change until Tasks 4–5 route red; covered
  end-to-end by Task 5's drive test.)
- Mirror: `scripts/night_shift_run.sh:183-192` (`_decide` env forwarding).
- Validate: `bash scripts/night_shift_run.test.sh` (still green; no regression).

### Task 4: `dispatch` — retry arms (unified) + escalate arm
- File: `scripts/night_shift_run.sh` (+ `scripts/night_shift_run.test.sh`)
- Action: UPDATE
- Implement:
  1. Tests first (Slice B): (B-reimpl) `retry-reimplement` on a repo with `feat/{N}-{slug}` +
     a real worktree holding `.agents/plans/{slug}.plan.md` → `/implement <wt>/.agents/plans/{slug}.plan.md`
     in `cwd=<wt>`, records `phase=implement`. (B-replan) `retry-replan` → `/plan {N}` in `cwd=<wt>`,
     records `phase=plan`. (B-escalate) `set-phase validate` + `incr-attempts`×3 + a fake
     `NIGHT_SHIFT_NOTIFY` logging its args → `escalate` calls notify with level `fail` and a
     message containing the phase (`validate`) and the attempt count (`3`); sets the escalated
     marker (`get-escalated → 1`); runs **no** `claude` and **no** `gh pr create`. Re-confirm
     B1/B2 (run-plan/run-implement) still pass under the unified arms. Run → new cases FAIL.
  2. Add a `NOTIFY="${NIGHT_SHIFT_NOTIFY:-$ROOT/.claude/hooks/notify.sh}"` external near
     `CLAUDE`/`GH` (`:33-40`). Rework `dispatch`:
     - `run-plan|retry-replan)` → `dir="$(_artifact_root "$branch")"; claude_run "$dir" "/plan ${n}"; bash "$STORE" set-phase "$n" plan`.
     - `run-implement|retry-reimplement)` → `dir="$(_artifact_root "$branch")"; pp="$(_plan_path_in "$dir" "$slug")"; claude_run "$dir" "/implement ${pp}"; bash "$STORE" set-phase "$n" implement`.
     - `escalate)` → read `phase`/`attempts` from `$STORE`; `"$NOTIFY" fail "Night Shift escalation" "#${n}: ${phase} gate red after ${attempts} attempts — needs human triage" || true` (best-effort, notify.sh never fails); **then** `bash "$STORE" set-escalated "$n"`. (Notify first, mark second → biases to alert-delivery; the marker guarantees exactly-once across normal re-runs.)
     - `run-validate)`, `open-pr)`, `noop)` unchanged.
- Mirror: `scripts/night_shift_run.sh:153-165` (validate/open-pr resolution); `.claude/hooks/validate_gate.py:100-110` (notify DI + call).
- Validate: `bash scripts/night_shift_run.test.sh` → Slice B green (incl. B1/B2/B5 no-push invariant).

### Task 5: `run` loop — increment on red, accept new tokens, MAX_ITERS
- File: `scripts/night_shift_run.sh` (+ `scripts/night_shift_run.test.sh`)
- Action: UPDATE
- Implement:
  1. Test first (Slice C): (C-fail) SIM drive where `/validate` **never** greens (fake claude
     `/plan`→writes plan, `/implement`→writes report, `/validate`→no-op leaving it red), K=3.
     Assert: reaches terminal `done: #N` and releases the claim; the ladder fires
     `/implement` (reimplement) then `/plan` (replan) in that order; **exactly one** notify call
     with `3` + `validate` in the message; `get-escalated → 1` after; and a **second** `run`
     immediately no-ops (decider `noop`, **no** second notify, no dispatch). Needs
     `NIGHT_SHIFT_MAX_ITERS` at its new default (≥10) or set explicitly ≥12. Run → FAILS
     (loop rejects `retry-*`/`escalate` as "unexpected decision").
  2. In `run`, before `_decide`: if the snapshot's `GATE == red`, `bash "$STORE" incr-attempts "$n" >/dev/null` then re-run `snap="$(gather_snapshot "$n")"` so `ATTEMPTS` reflects the increment (double-gather — pure read, avoids a fragile in-place patch). Add `retry-reimplement|retry-replan|escalate` to the dispatch case arm (`:225`). Change the `MAX_ITERS` default (`:38`) to derive from K: `MAX_ITERS="${NIGHT_SHIFT_MAX_ITERS:-$(( 3 * MAX_ATTEMPTS_K + 6 ))}"` with a comment showing the worst-case arithmetic; keep honoring an explicit `NIGHT_SHIFT_MAX_ITERS`.
- Mirror: `scripts/night_shift_run.sh:197-237` (run loop, claim gate, terminal release); `scripts/night_shift_run.test.sh:290-347` (C3/C4/C5 drive-test scaffolding + SIM fakes).
- Validate: `bash scripts/night_shift_run.test.sh` → **all** Slices green.

### Task 6: Live end-to-end probe (operator-gated) — ground the re-implement/re-plan risks
- File: none (probe; findings recorded in the Phase-4 report)
- Action: VERIFY
- Implement: on a throwaway `ready-for-agent` Issue with a deliberately-failing check, run the
  real executor (`env -u ANTHROPIC_API_KEY bash scripts/night_shift_run.sh <N>`) and observe the
  full ladder in the **real worktree**: a red gate advances `attempts`, the ladder re-runs
  `/implement` (attempt 1) then `/plan` (attempt 2), escalation fires **once** to the phone
  naming phase+attempts, and a re-run is a no-op. This is the #61 Seam-3 pattern — it grounds
  the two ASSUMED external-behavior claims. Record **both** of these as explicit PASS/FAIL
  probe outcomes in the report:
  1. **re-`/implement` resumes & fixes** — the attempt-1 `/implement` re-enters the existing
     worktree and actually changes the failing code (not a "tasks already done" no-op).
  2. **retry-replan propagation (the weakest link)** — after attempt-2's `/plan`, confirm the
     **regenerated plan is the one the next `/implement` reads** (same `{slug}.plan.md` the
     branch tracks), i.e. the re-plan is not silently ignored / orphaned by a filename mismatch.
     Note the exact filename `/plan` emitted vs. `{slug}`.
- On a FAIL of outcome 2: this is **not blocking** #62 (its AC is the wiring, which the unit
  tests prove). File a **follow-up issue** — the likely fix is pinning `/plan`'s re-plan output
  to `{slug}.plan.md` (a small `/plan`-contract enhancement to accept a target path / overwrite
  in place), deliberately kept out of this slice.
- Note: spends real subscription credits and requires the operator (headless auth per memory:
  `env -u ANTHROPIC_API_KEY`; push-dial is operator-only). If credentials/time are unavailable,
  mark E2E "deferred to operator" in the report and rely on the unit SIM for the gate.
- Validate: operator observation matches the acceptance criteria below; outcomes 1 & 2 recorded
  as explicit PASS/FAIL (a FAIL of 2 → follow-up issue filed, #62 still ships).

## Validation
Unit gate (all must print `All tests passed.`):
```bash
bash scripts/loop_state.test.sh          # Task 1
bash scripts/night_shift_run.test.sh     # Tasks 2–5 (Slices A/B/C)
bash scripts/night_shift_decide.test.sh  # unchanged — regression guard
bash scripts/night_shift_retry.test.sh   # unchanged — regression guard
bash scripts/notify.test.sh              # notify.sh untouched — regression guard
bash .claude/validate.sh                 # PIV invariant gate (Stop-hook parity)
```
Also confirm the no-regression invariants inside `night_shift_run.test.sh`: B5 (dispatch performs
no `gh`/push/PR of its own), C3 (happy path still reaches `done` in PIV order), C4 (PR-open
terminal no-op), C5 (explicit `MAX_ITERS` runaway stop).

End-to-end (Task 6, operator): red gate → ladder → single escalation naming phase+attempts →
terminal no-op on re-run.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors (every `*.test.sh` above green; existing suites unregressed)
- [ ] On a red gate the executor re-runs `/implement` (attempt 1) then `/plan` (attempt 2) per the decider's ladder
- [ ] At K attempts the task stops and **exactly one** `escalate` notification (`notify.sh fail`) fires
- [ ] The escalation message names the failed phase (`validate`) + attempt count
- [ ] Executor is a no-op when terminal (PR open **or** escalated) — no re-open, no duplicate work, no second notification
- [ ] Attempt count is read from / advanced in durable `loop_state` across retries; `escalated` persists across runs
- [ ] Follows existing patterns (decider unchanged; `_artifact_root`/`_plan_path_in` reused; notify DI mirrors `validate_gate.py`)
- [ ] Every external-behavior claim is VERIFIED by a probe, or carried as an explicit risk (re-`/implement`/re-`/plan` → live probe, Task 6)
- [ ] End-to-end behavior verified (Task 6) or explicitly deferred-to-operator in the report
