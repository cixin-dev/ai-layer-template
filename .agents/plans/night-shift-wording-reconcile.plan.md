# Plan: Reconcile "event-driven / concurrency dial" wording with the shipped synchronous serial drain

## Summary
The Night Shift PRD and canonical docs oversell the shipped outer loop: they call the happy
path **"event-driven"** and frame the ~5-min poll as **"recovering dropped completion events"**,
and they present concurrency as a **"graduatable dial (1→N) without re-architecting."** The
shipped loop (`scripts/night_shift_loop.sh`) is a **synchronous serial busy-drain in one process
plus a ~5-min safety-net poll**: there is no async event channel, and the concurrency "dial" is
only a reject-if-not-1 guard with no parallel-dispatch path. This is a **wording/accuracy fix
only** — zero behavior change. Correct the PRD, CONTEXT.md, ADR-0023's live-mechanism sentence,
and the loop runbook so no canonical doc implies an event bus or a ready-to-graduate concurrency
mechanism that does not exist.

## User Story
As a future reader of the PRD/canonical docs, I want the trigger model and concurrency dial
described exactly as shipped (synchronous zero-idle drain + discovery/liveness poll; an
enforce-serial guard with N flagged as unbuilt), so that I don't infer an async event channel or
a ready-to-graduate concurrency mechanism and build/plan on a false premise.

## Metadata
| Field | Value |
|-------|-------|
| Type | BUG_FIX (documentation accuracy) |
| Complexity | LOW |
| Systems affected | `.agents/prds/piv-ralph-loop.prd.md`, `CONTEXT.md`, `docs/adr/0023-*.md`, `.agents/reports/night-shift-loop-runbook.md` |
| Issue | #86 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| The happy path is a **synchronous serial drain in one process**, not an async event channel | **VERIFIED** | Read `scripts/night_shift_loop.sh:87-116`: `drain()` is `while :; do n=$(select_issue); "$RUN" "$n"; done` — a blocking executor call then immediate re-select. No subscription/event primitive anywhere in the 159-line file. |
| The ~5-min poll's real job is **discovering newly-`ready-for-agent` Issues + liveness**, not recovering dropped events | **VERIFIED** | `night_shift_loop.sh:118-136`: `loop()` runs `drain` then `sleep POLL_INTERVAL`; `select_issue` (60-72) re-runs `gh issue list --label ready-for-agent`, i.e. re-discovers newly-labelled Issues. There is no event to "drop", so nothing to recover. |
| The concurrency "dial" is only an **enforce-serial guard** (reject ≠1); no parallel-dispatch path exists | **VERIFIED** | `night_shift_loop.sh:76-81` `_require_serial()` exits 2 on `CONCURRENCY != 1`; every `drain`/`loop` runs strictly one `"$RUN"` at a time. Graduating to N requires building parallel dispatch, not changing a number. |
| The **only** canonical docs carrying the drift are the PRD, CONTEXT.md, ADR-0023 (line 11), and the loop runbook | **VERIFIED** | `grep -rn -i "event-driven\|event channel\|dropped.*completion event\|concurrency.*dial\|1→N"` over `*.md` (excluding `node_modules`, `.agents/plans/completed`): drift hits are PRD (US-18/19/20, Trigger-model, Concurrency decisions), CONTEXT.md:260-263, ADR-0023:11, runbook:93. See "Out of scope" for the deliberately-untouched artifacts. |
| Editing ADR-0023's Context sentence does **not** reverse its decision | **VERIFIED (by inspection)** | ADR-0023's Decision is "triggers schedule, never judge" (lines 25-51); line 11 is a *Context* sentence describing the live trigger mechanism. Swapping the noun "event channel"→"synchronous trigger chain" makes the description accurate and leaves the decision 100% intact (the decision reads *better* without the async implication). |
| The validate gate (`piv_check.sh`) passes on a docs-only change | **ASSUMED (low risk)** | `.claude/validate.sh` runs `scripts/piv_check.sh` — PIV *structural* checks (plan-is-first-commit, report presence, range checks on a feature branch); it runs no unit tests touched by docs. Implement de-risks by running `bash .claude/validate.sh` on the branch as Task-final validation. |

**Risk — ADR append-only convention.** This repo treats ADRs as append-only, one-decision-per-ADR
(ADR-0023:62). Mitigation: the ADR-0023 edit is a **single-noun accuracy fix inside the Context
section** describing the *live* system (now known to be synchronous), not a decision change — the
one class of ADR edit that is legitimate. ADR-0024's deferred-candidates list is left untouched
(see Out of scope) precisely to respect this convention.

## Patterns to Follow

The shipped reality to mirror in the prose — the loop is a blocking re-select, not an event bus:
```bash
# SOURCE: scripts/night_shift_loop.sh:87-116  (drain — synchronous serial busy-drain)
drain() {
  _require_serial || return $?
  local last=""
  while :; do
    if _stopped; then echo "kill switch: ..."; return 0; fi
    n="$(select_issue)"          # re-queries gh issue list --label ready-for-agent
    [ -n "$n" ] || return 0
    ...
    "$RUN" "$n" || rc=$?         # BLOCKING executor call — returns, then loop re-selects
    last="$n"
  done
}
```
```bash
# SOURCE: scripts/night_shift_loop.sh:76-81  (the "dial" is a reject-if-not-1 guard)
_require_serial() {
  [ "$CONCURRENCY" = "1" ] || {
    echo "night_shift_loop: serial only in v1 (concurrency=$CONCURRENCY reserved for a later graduation)" >&2
    return 2
  }
}
```

Prose already-good self-defined usage to mirror (keep the parenthetical, drop the bare adjective):
```
# SOURCE: .agents/reports/night-shift-loop-runbook.md:93 (current)
is better for event-driven throughput (drain loop re-selects immediately after each executor
returns, with no fixed idle gap).
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.agents/prds/piv-ralph-loop.prd.md` | UPDATE | US-18, US-19, US-20, and the "Trigger model = hybrid" + "Concurrency is a dial" implementation decisions |
| `CONTEXT.md` | UPDATE | Night Shift entry, lines 260-263 (event-driven + dropped-completion-events framing) |
| `docs/adr/0023-night-shift-triggers-schedule-not-judge.md` | UPDATE | line 11 Context sentence: "event channel" → synchronous framing (decision untouched) |
| `.agents/reports/night-shift-loop-runbook.md` | UPDATE | line 93: drop bare "event-driven" adjective (keep the accurate parenthetical) |

## Tasks
Ordered; each edit is a literal find/replace. After all edits, run the E2E grep sweep + gate.

### Task 1: PRD — US-19 (poll = discovery + liveness, not dropped-event recovery)
- File: `.agents/prds/piv-ralph-loop.prd.md`
- Action: UPDATE (lines 89-90)
- Implement: replace
  ```
  19. As an operator, I want a ~5-minute poll to pick up newly-`ready` Issues and to catch any
      dropped completion event, so that the loop makes progress even if an event is missed.
  ```
  with
  ```
  19. As an operator, I want a ~5-minute poll to discover newly-`ready` Issues and confirm the
      loop is alive, so that freshly-labelled work gets picked up and a wedged loop is visible.
  ```
- Mirror: shipped behavior in `scripts/night_shift_loop.sh:118-136,60-72`
- Validate: `grep -n "dropped completion event" .agents/prds/piv-ralph-loop.prd.md` → no US-19 hit

### Task 2: PRD — US-20 (define "event-driven" as synchronous zero-idle drain)
- File: `.agents/prds/piv-ralph-loop.prd.md`
- Action: UPDATE (lines 91-92)
- Implement: replace
  ```
  20. As an operator, I want a finished phase to immediately trigger the next phase
      (event-driven happy path), so that a task doesn't idle up to 5 minutes at each transition.
  ```
  with
  ```
  20. As an operator, I want a finished phase to immediately trigger the next phase
      (a synchronous zero-idle drain — the phase call returns and the loop re-selects at once,
      in one process, not an async event), so that a task doesn't idle up to 5 minutes at each
      transition.
  ```
- Mirror: `scripts/night_shift_loop.sh:87-116`
- Validate: `grep -n "event-driven happy path" .agents/prds/piv-ralph-loop.prd.md` → nothing

### Task 3: PRD — US-18 (concurrency = guarded enforce-serial dial; N flagged as unbuilt)
- File: `.agents/prds/piv-ralph-loop.prd.md`
- Action: UPDATE (lines 87-88)
- Implement: replace
  ```
  18. As an operator, I want concurrency to be a graduatable dial (1 → N), so that I can raise
      throughput later without re-architecting.
  ```
  with
  ```
  18. As an operator, I want concurrency to be a guarded dial that today enforces serial (=1 —
      any other value is rejected), so that v1 blast radius stays bounded; graduating to N is
      flagged as later work that requires building real parallel dispatch, not just raising the
      number.
  ```
- Mirror: `scripts/night_shift_loop.sh:76-81`
- Validate: `grep -n "without re-architecting" .agents/prds/piv-ralph-loop.prd.md` → nothing

### Task 4: PRD — "Trigger model = hybrid" decision
- File: `.agents/prds/piv-ralph-loop.prd.md`
- Action: UPDATE (lines 154-158)
- Implement: replace
  ```
  - **Trigger model = hybrid.** Event-driven on the happy path (a finished phase immediately
    triggers the next), with a ~5-minute poll as a safety net that (a) discovers newly-`ready`
    Issues and (b) recovers any dropped completion event. The runtime substrate (cron /
    `/loop`+`/routines` / a Workflow engine) is deliberately NOT fixed here — it is a
    `/plan`-phase decision. This PRD fixes only behavior.
  ```
  with
  ```
  - **Trigger model = hybrid.** A synchronous zero-idle drain on the happy path (each finished
    phase returns and the loop re-selects the next work at once, in one process — there is no
    async event channel), with a ~5-minute poll as a safety net that (a) discovers newly-`ready`
    Issues and (b) provides liveness. The runtime substrate (cron /
    `/loop`+`/routines` / a Workflow engine) is deliberately NOT fixed here — it is a
    `/plan`-phase decision. This PRD fixes only behavior.
  ```
- Mirror: `scripts/night_shift_loop.sh:87-136`
- Validate: `grep -n "Event-driven on the happy path\|dropped completion event" .agents/prds/piv-ralph-loop.prd.md` → nothing

### Task 5: PRD — "Concurrency is a dial" decision
- File: `.agents/prds/piv-ralph-loop.prd.md`
- Action: UPDATE (lines 177-179)
- Implement: replace
  ```
  - **Concurrency is a dial, default 1.** v1 runs serial (one task through the full pipeline at
    a time). The design reserves the existing `piv-loop` "parallel-implement / serial-landing"
    protocol as the graduation path to N. Raising the dial is a later, deliberate action.
  ```
  with
  ```
  - **Concurrency is a guarded dial, default 1.** v1 runs serial (one task through the full
    pipeline at a time); the dial today is only an *enforce-serial guard* — any value ≠ 1 is
    rejected and there is no parallel-dispatch path. The design reserves the existing `piv-loop`
    "parallel-implement / serial-landing" protocol as the graduation path to N, but graduating is
    real parallel-dispatch work, not just raising the number — a later, deliberate action.
  ```
- Mirror: `scripts/night_shift_loop.sh:76-81`
- Validate: `grep -n "enforce-serial guard" .agents/prds/piv-ralph-loop.prd.md` → present

### Task 6: CONTEXT.md — Night Shift entry
- File: `CONTEXT.md`
- Action: UPDATE (lines 260-263)
- Implement: replace
  ```
  reviews the PR. The loop advances event-driven on the happy path; a **scheduling poll** — a periodic
  machine sweep (*not* a human's dashboard-checking) — is the backstop that picks up newly
  `ready-for-agent` Issues and recovers dropped completion events (its runtime substrate stays a
  `/plan` decision; the loop's triggers *schedule* phases but never *judge* completion — ADR-0023).
  ```
  with
  ```
  reviews the PR. The loop advances by a **synchronous zero-idle drain** on the happy path (each
  finished phase returns and the loop re-selects the next work at once, in one process — not an
  async event channel); a **scheduling poll** — a periodic machine sweep (*not* a human's
  dashboard-checking) — is the backstop that discovers newly `ready-for-agent` Issues and keeps the
  loop live (its runtime substrate stays a `/plan` decision; the loop's triggers *schedule* phases
  but never *judge* completion — ADR-0023).
  ```
  NOTE: preserve the exact leading text `reviews the PR.` — line 260 begins mid-sentence from
  line 259 (`The human keeps both bookends … the **boundary gate**`). Match the full line.
- Mirror: shipped behavior; ADR-0023 (schedule-not-judge clause preserved verbatim)
- Validate: `grep -n "event-driven\|dropped completion event" CONTEXT.md` → nothing

### Task 7: ADR-0023 — Context sentence noun fix (decision untouched)
- File: `docs/adr/0023-night-shift-triggers-schedule-not-judge.md`
- Action: UPDATE (line 11)
- Implement: replace
  ```
  `/implement` triggers `/validate`, and a **scheduling poll** backstops that event channel. These
  ```
  with
  ```
  `/implement` triggers `/validate`, and a **scheduling poll** backstops that synchronous trigger
  chain. These
  ```
  Do NOT touch the Decision/Consequences sections — only this one Context noun.
- Mirror: `scripts/night_shift_loop.sh:87-116`
- Validate: `grep -n "event channel" docs/adr/0023-night-shift-triggers-schedule-not-judge.md` → nothing

### Task 8: Runbook — drop bare "event-driven" adjective (keep parenthetical)
- File: `.agents/reports/night-shift-loop-runbook.md`
- Action: UPDATE (line 93)
- Implement: replace
  ```
  is better for event-driven throughput (drain loop re-selects immediately after each executor
  ```
  with
  ```
  is better for zero-idle throughput (drain loop re-selects immediately after each executor
  ```
- Mirror: the parenthetical already correctly describes the synchronous re-select
- Validate: `grep -n "event-driven" .agents/reports/night-shift-loop-runbook.md` → nothing

## Validation

**Project gate:**
```bash
bash .claude/validate.sh      # runs scripts/piv_check.sh (PIV structural checks); docs-only → pass
```

**E2E acceptance sweep — "event-driven" across canonical docs surfaces only corrected/defined usage:**
```bash
# 1) No bare async-event framing left in canonical docs (PRD, CONTEXT, ADRs):
grep -rn -i "event-driven\|event channel\|dropped.*completion event" \
  CONTEXT.md .agents/prds/piv-ralph-loop.prd.md docs/adr/ \
  | grep -v "docs/adr/0024"        # ADR-0024's deferred-candidates list is intentionally kept (see Out of scope)
# → EXPECT: no output (empty). Any hit that is not ADR-0024 = fail.

# 2) Concurrency dial now described as an enforce-serial guard with N flagged unbuilt:
grep -n "enforce-serial guard\|guarded dial" .agents/prds/piv-ralph-loop.prd.md
# → EXPECT: US-18 + "Concurrency is a guarded dial" decision both hit.

# 3) Poll reframed to discovery + liveness (no dropped-event recovery):
grep -n "dropped completion event\|recovers dropped" CONTEXT.md .agents/prds/piv-ralph-loop.prd.md
# → EXPECT: empty.

# 4) Surgical-diff check — only the 4 intended files changed:
git diff --name-only
# → EXPECT exactly: .agents/prds/piv-ralph-loop.prd.md  CONTEXT.md
#                   docs/adr/0023-night-shift-triggers-schedule-not-judge.md
#                   .agents/reports/night-shift-loop-runbook.md
```

**PR body:** must carry the Traditional Chinese `## 變更說明` section (ADR-0022) — authored by
`/validate` Phase 5. Summarize: 校正夜班外層迴圈的文件用語 —「event-driven / 掉事件回收 /
concurrency 撥盤」改為「同步序列 drain + 探索/存活輪詢 + enforce-serial 守門」以符合實際出貨行為;
純文件修正,不改任何 loop 腳本行為。

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `bash .claude/validate.sh` passes with zero errors
- [ ] PRD no longer implies an async event channel; "event-driven" removed or defined as "synchronous zero-idle drain" (Tasks 2, 4)
- [ ] Poll described as newly-ready-Issue discovery + liveness, not dropped-event recovery (Tasks 1, 4, 6)
- [ ] Concurrency dial described as an enforce-serial guard, N-graduation flagged as unbuilt (Tasks 3, 5)
- [ ] CONTEXT.md + ADR-0023 + runbook updated to match; E2E sweep #1 returns empty (Tasks 6, 7, 8)
- [ ] `git diff --name-only` shows exactly the 4 intended files (no collateral edits)
- [ ] Every drift claim VERIFIED against `scripts/night_shift_loop.sh` (done in this plan)
- [ ] PR body carries the `## 變更說明` section (added by `/validate`)

## Out of scope (deliberately NOT edited — record, don't rewrite history)
- **No behavior change.** Not one line of `scripts/night_shift_loop.sh` (or any script) changes.
  This is prose accuracy only. Building a real async event channel or parallel-dispatch concurrency
  is a separate future enhancement.
- **`docs/adr/0024-*.md:48`** ("event channel + scheduling poll") — **left as-is.** That phrase is a
  *deferred-candidates list* for a decision ADR-0024 explicitly punts to #63 ("How the executor is
  invoked repeatedly … is a separate decision"). It does not claim the shipped loop HAS an event
  channel; rewriting it would falsify the historical record of what was anticipated. The shipped
  outcome is recorded (corrected) in the PRD/CONTEXT/runbook instead. If a reviewer wants it softened,
  that is a one-word discretionary follow-up, not part of this fix.
- **`.agents/reports/night-shift-hybrid-trigger-loop-report.md`, `night-shift-prd-vs-impl-audit-report.md`,
  `notify-validate-events-report.md`** — historical point-in-time reports (implementation report, the
  audit that *spawned* #86, and a report about the unrelated tmux/ntfy notification channel). Editing
  them rewrites history; the audit report *correctly* documents the drift being fixed here.
