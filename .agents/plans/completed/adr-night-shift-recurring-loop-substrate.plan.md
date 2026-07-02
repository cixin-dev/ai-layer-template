# Plan: ADR — Night Shift recurring-loop runtime substrate (close the deferred thread)

## Summary
Write a new ADR (`docs/adr/0026-…`) that records the **recurring-invocation / outer-loop
scheduler substrate** the Night Shift actually shipped in #81 (`scripts/night_shift_loop.sh`):
a plain Bash drain+poll loop that selects the next grabbable `ready-for-agent` Issue and hands
it to the ADR-0024 executor, draining back-to-back while work exists and sleeping ~5 min only
when the queue is empty (serial v1, file+signal kill switch). ADR-0024 §3 explicitly **deferred**
this "recurring event+poll scheduler" decision; the PRD and CONTEXT.md still call it an unfixed
"`/plan`-phase decision." The ADR captures the choice, the alternatives the PRD named (cron /
`/loop`+`/routines` / Workflow engine) with a rejection reason each, and the v1 limits (serial,
synchronous drain, idle-poll quiescence) — then we close the three dangling "deferred" pointers so
no reader is left following a stale thread. This is **documentation only**; the substrate itself
is unchanged.

## User Story
As a future reader (or implementer) of the Night Shift, I want a single findable ADR that states
which runtime substrate was chosen for the recurring loop and why, so that the "substrate is a
`/plan`-phase decision" thread the PRD deliberately left open has a durable, non-dangling answer.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW (documentation) |
| Complexity | LOW |
| Systems affected | `docs/adr/` (new ADR), `docs/adr/0024` (Status annotation), `.agents/prds/piv-ralph-loop.prd.md`, `CONTEXT.md` |
| Issue | #87 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| The next sequential ADR number is **0026** | VERIFIED | `ls docs/adr/` — highest is `0025-night-shift-trigger-label-is-ready-for-agent.md`; no `0026`. |
| The shipped substrate = shell drain+poll loop invoking the executor per Issue; serial v1; ~5-min idle poll; file+signal kill switch | VERIFIED | Read `scripts/night_shift_loop.sh:1-159`: `drain()` loops `select_issue`→`"$RUN" "$n"` back-to-back; `loop()` calls `drain` then `sleep $POLL_INTERVAL` (default 300); `_stopped`=`.night-shift/stop` file; `trap … INT TERM`. |
| Serial-only is enforced (concurrency≠1 rejected) | VERIFIED | Probe: `NIGHT_SHIFT_CONCURRENCY=2 bash scripts/night_shift_loop.sh drain` → `serial only in v1 (concurrency=2 …)`, `rc=2`. Guard short-circuits before any gh/executor call (`drain()` → `_require_serial \|\| return $?`). |
| ADR-0024 §3 is the deferral this ADR resolves; it deferred to **#63**, which **#81** closed | VERIFIED | ADR-0024:47-49 "The recurring event+poll scheduler is deferred to #63." `gh pr view 81` body ends "Closes #63"; git log `176991b … (#81)`. |
| The PRD names exactly these three alternatives to fix | VERIFIED | PRD:156-158 and PRD:248-249 both list "cron / `/loop`+`/routines` / a Workflow engine". |
| Three live "deferred / `/plan`-phase" pointers exist to close | VERIFIED | PRD:156-158, PRD:248-249; ADR-0024:47-49; CONTEXT.md:262 ("its runtime substrate stays a `/plan` decision"). |
| ADRs are append-only; prior ADRs are annotated via the **Status line**, not body-rewritten | VERIFIED | ADR-0025:43-44 "Those append-only ADRs need no edit; the mapping is canonical here." Existing Status lines already carry relations ("**depends on** ADR-0023", "**sharpens ADR-0010**"). → We annotate ADR-0024's Status line only; the new ADR carries the canonical decision. |
| The ADR must stay English; the zh `## 變更說明` lives in the PR body, not the ADR | VERIFIED | CLAUDE.md Do-not: "Canonical docs (`CONTEXT.md`, ADRs) stay English"; ADR-0022 / zh-summary rule scopes zh to PR bodies. |
| `validate.sh` gate passes on a docs-only change | ASSUMED | `.claude/validate.sh` runs `scripts/piv_check.sh` (PIV artifact state). No code touched. De-risk: Implement runs `bash .claude/validate.sh` after the edits (Task 5). |

### Design decision to confirm (the one non-obvious call)
**How to close the ADR-0024 §3 pointer without violating the append-only ADR convention.**
ADR-0025 set the precedent that prior ADRs "need no edit." Standard ADR practice keeps the
decision *body* immutable but treats the **Status line** as the sanctioned mutation point for
recording resolution/supersession. Recommendation (this plan): **do not rewrite ADR-0024's body**;
append a single forward pointer to its **Status line** ("…; the deferred recurring-scheduler
substrate (§3) is now recorded in ADR-0026"), and have the new ADR reference back to ADR-0024 §3.
The PRD and CONTEXT.md (living docs, routinely reconciled — cf. ADR-0025's stale-`ready` sweep) get
normal forward-pointer edits. This satisfies AC#4 ("linked from … PRD further-notes and/or
ADR-0024, so no dangling pointer remains") while honoring append-only. If the reviewer prefers zero
ADR edits, fall back to: leave ADR-0024 untouched and rely on the new ADR's back-reference + the
PRD/CONTEXT pointers — still AC-compliant via the "and/or".

## Patterns to Follow

**ADR file shape** (mirror the three most recent Night Shift ADRs):
```markdown
# <decision stated as a sentence>

**Status:** Accepted (2026-07-02); relates to the Night Shift PRD
(`.agents/prds/piv-ralph-loop.prd.md`, #63/#81) and **resolves the recurring-scheduler substrate
deferred by ADR-0024 §3**.

## Context
…which mechanism invokes the executor repeatedly, and why it was left open…

## Decision
…the chosen substrate, as numbered points…

## Why this over the alternatives
- **cron** — rejected: …
- **`/loop` + `/routines`** — rejected: …
- **Workflow engine / subagents** — rejected: …

## Consequences
…v1 limits + what a reversal would require…
```
<!-- SOURCE: docs/adr/0023-night-shift-triggers-schedule-not-judge.md:1-79 (Status line w/ relation,
     Context→Decision→Why-alternatives→Consequences, "a future change … is a reversal … must be
     recorded as a superseding one") and docs/adr/0024-…-own-clone.md:1-95 (numbered Decision
     points; "## Why this over the alternatives" bullet-with-rejection style). -->

**Status-line annotation on a prior ADR** (append-only-safe forward pointer):
```markdown
**Status:** Accepted (2026-06-30); **depends on** ADR-0023 … Leaves the PIV artifact lifecycle
… **unchanged**.
```
<!-- SOURCE: docs/adr/0024-…-own-clone.md:3-5 — append "; the recurring-scheduler substrate it
     deferred (§3) is now recorded in ADR-0026." Do NOT touch the Decision body. -->

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `docs/adr/0026-night-shift-recurring-loop-substrate-shell-drain-poll.md` | CREATE | The decision record (primary deliverable). |
| `docs/adr/0024-night-shift-executor-substrate-headless-claude-own-clone.md` | UPDATE | Status-line forward pointer → ADR-0026 (append-only annotation, no body change). |
| `.agents/prds/piv-ralph-loop.prd.md` | UPDATE | Point the two "substrate is a `/plan`-phase decision" spots + add a Further Notes bullet → ADR-0026. |
| `CONTEXT.md` | UPDATE | Replace the "runtime substrate stays a `/plan` decision" parenthetical (line ~262) with the ADR-0026 answer. |

## Tasks
Ordered, atomic, each independently verifiable.

### Task 1: Write the new ADR
- File: `docs/adr/0026-night-shift-recurring-loop-substrate-shell-drain-poll.md`
- Action: CREATE
- Mirror: `docs/adr/0023-night-shift-triggers-schedule-not-judge.md:1-79`, `docs/adr/0024-…-own-clone.md:1-95`
- Implement — English only, ADR house style. Include:
  - **H1 title** (sentence form), e.g.: *"Night Shift recurring-invocation substrate is a shell drain+poll loop, not cron / `/loop` / a Workflow engine."*
  - **Status:** `Accepted (2026-07-02); relates to the Night Shift PRD (…, #63/#81); resolves the recurring event+poll scheduler substrate deferred by ADR-0024 §3; builds on ADR-0024 (executor substrate) and ADR-0023 (schedule-not-judge).`
  - **## Context** — Distinguish the two substrate questions: ADR-0024 fixed the **executor** substrate ("how each phase runs" = per-phase `claude -p` in the Night Shift's own clone) and **§3 deferred** the **recurring-invocation** substrate ("how the executor is invoked repeatedly" — event channel + scheduling poll, queue selection across many Issues, serial→N, kill switch). The PRD (`156-158`, `248-249`) called this a `/plan`-phase decision and fixed only behavior (hybrid trigger: event-driven happy path + ~5-min safety-net poll). #81 shipped it (`scripts/night_shift_loop.sh`, closes #63) but with no companion ADR — the decision lives only implicitly in the script and the #81 PR body. This ADR records it.
  - **## Decision** — numbered points, grounded in `scripts/night_shift_loop.sh`:
    1. **Substrate = a plain Bash outer loop** (`night_shift_loop.sh`) running in the Night Shift's own clone (ADR-0024). It holds **no phase logic**: it only `select`s the next grabbable Issue and hands it to the executor (`night_shift_run.sh`), which owns claim + phase-chaining (the `claude -p` per-phase substrate stays ADR-0024's). `loop:1-9`, `select_issue:60-72`.
    2. **Hybrid cadence realized as drain-then-poll.** `drain()` runs Issues back-to-back with **zero idle wait** while the ready set is non-empty (the event-driven happy path); `loop()` sleeps `NIGHT_SHIFT_POLL_INTERVAL` (**default 300s ≈ 5 min**) only when a drain pass finds nothing — the safety-net poll that re-discovers newly-ready Issues and recovers dropped completions. `drain:87-116`, `loop:118-136`.
    3. **Level-triggered on durable artifact state**, not an async event bus: selection reads the executor's side-effects (the `in-progress` claim label; `PR_OPEN`/`ESCALATED` from `snapshot`) so the loop is restartable/idempotent (consistent with ADR-0023's pure-state decider). A **no-progress guard** ends the pass if the same Issue re-selects after dispatch, backing a hot-spin off to the poll interval. `select_issue:60-72`, `drain:97-107`.
    4. **Serial v1** — `NIGHT_SHIFT_CONCURRENCY` defaults to 1; `_require_serial` rejects any other value (`rc 2`) — N reserved for a later graduation. `_require_serial:76-81`.
    5. **Kill switch** = a file sentinel (`.night-shift/stop`) **and** an INT/TERM trap. `_stopped:83`, `loop:120`.
    6. **DI seams test offline** — `gh`, the executor (`RUN`), and `sleep` are all injected, so the loop is exhaustively unit-tested with zero credit spend (`scripts/night_shift_loop.test.sh`). `header:17-28`.
  - **## Why this over the alternatives** — one bullet each with a rejection reason (the exact three the PRD named at `156-158`/`248-249`):
    - **cron** — external scheduler; nothing in-repo to commit or test; fixed-interval only, so it can't do the event-driven back-to-back drain (adds latency or hammers); doesn't address selection/claim. (Mirror ADR-0024's cron rejection at `70-71`.)
    - **`/loop` + `/routines`** — a long-lived self-reprompting **claude session** as the scheduler: costs credits to *wait*, is not testable offline, and blurs the isolation boundary the whole design protects (per-phase fresh sessions — ADR-0023/0024). PRD put it out of scope. (ADR-0024:72-74.)
    - **Workflow engine / subagents** — more orchestration machinery than a level-triggered selector needs, and a subagent isn't a full PIV session (doesn't expand the slash command / load hooks — ADR-0024:75-77). Simplicity-first: the executor already owns claim + phase-chaining + terminal state, so a shell `while`+`select`+`sleep` is the minimum that works.
  - **Why chosen for v1** (fold into the alternatives section or a short lead-in): simplicity-first (CLAUDE.md) — the outer loop is a thin selection wrapper; reuses ADR-0024's `claude -p` substrate with **zero new runtime dependency**; in-repo, committable, offline-testable; level-triggered → restartable.
  - **## Consequences / known limits (v1)** — state plainly:
    - **Serial only** (concurrency=1; N is a reserved graduation).
    - **Synchronous drain** — the loop **blocks** on each `"$RUN" "$n"`; one slow task stalls the whole queue.
    - **Quiescence = idle-poll, not process-exit** — the loop is a **persistent process**; a drained queue → *sleep*, not exit (only the kill switch / `MAX_POLLS` stop it). "Idle" ≠ "done."
    - **"Event-driven" is level-triggered re-selection**, not a webhook/event channel; a dropped completion is recovered by the **next poll**, not by an interrupt.
    - A future change to a different substrate (cron / Workflow engine / long-lived session) is a **reversal** of this ADR and must be recorded as a superseding one (mirror ADR-0023:78-79 / ADR-0024:88-91).
- Validate: `bash .claude/validate.sh`; file exists; `grep -c` confirms cron, `/loop`, Workflow, ADR-0024, serial, "synchronous", "idle-poll"/"process-exit" all present.

### Task 2: Annotate ADR-0024's Status line (append-only forward pointer)
- File: `docs/adr/0024-night-shift-executor-substrate-headless-claude-own-clone.md`
- Action: UPDATE
- Implement: append to the **Status line only** (lines 3-5) a forward pointer, e.g. `; the recurring event+poll scheduler it deferred (§3) is now recorded in ADR-0026.` **Do not modify §3 or any Decision body text** — append-only.
- Mirror: `docs/adr/0024-…-own-clone.md:3-5`
- Validate: `git diff` shows only the Status line changed; §3 (`47-49`) byte-identical.

### Task 3: Close the PRD pointers
- File: `.agents/prds/piv-ralph-loop.prd.md`
- Action: UPDATE
- Implement — three minimal edits, each a forward pointer (keep prose intact, append the pointer):
  1. Design Decisions "Trigger model = hybrid" (`156-158`): after "…it is a `/plan`-phase decision." add "**(now decided — see ADR-0026: shell drain+poll loop.)**"
  2. Out of Scope (`248-249`): "Fixing the runtime substrate … A `/plan`-phase decision." → append "**— now recorded in ADR-0026.**"
  3. **## Further Notes** (`256+`): add a bullet, e.g. *"**Runtime substrate — decided.** The `/plan`-phase substrate question left open above is answered in ADR-0026: a shell drain+poll outer loop (`night_shift_loop.sh`) invoking the ADR-0024 executor. No dangling 'deferred' pointer remains."*
- Mirror: existing PRD bullet style (`256-267`).
- Validate: `grep -n "ADR-0026" .agents/prds/piv-ralph-loop.prd.md` → 3 hits; the phrase "`/plan`-phase decision" no longer appears without an adjacent ADR-0026 pointer.

### Task 4: Reconcile the CONTEXT.md glossary pointer
- File: `CONTEXT.md`
- Action: UPDATE
- Implement: in the **Night Shift** entry (`262-263`), replace "(its runtime substrate stays a `/plan` decision;" with "(its runtime substrate is ADR-0026's shell drain+poll loop;" — keep the rest of the parenthetical ("the loop's triggers *schedule* phases but never *judge* completion — ADR-0023") unchanged. English only.
- Mirror: `CONTEXT.md:260-263`
- Validate: `grep -n "runtime substrate" CONTEXT.md` shows the ADR-0026 wording; no residual "stays a `/plan` decision".

### Task 5: Full-repo dangling-pointer sweep + gate
- File: (verification only)
- Action: n/a
- Implement: confirm no stale "deferred/`/plan`-phase" substrate pointer survives anywhere, then run the gate.
- Validate:
  - `grep -rniE "runtime substrate.*(/plan|deferr)|deferred to #63" docs/ .agents/prds/ CONTEXT.md` → every remaining hit also carries an `ADR-0026` reference (or is ADR-0024's now-annotated Status line). Zero bare/dangling hits.
  - `bash .claude/validate.sh` → exits 0.

## Validation
- **Gate:** `bash .claude/validate.sh` (runs `scripts/piv_check.sh`) exits 0.
- **ADR presence & format:** `docs/adr/0026-…md` exists; H1 sentence title; `**Status:**` line; `## Context` / `## Decision` / `## Why this over the alternatives` / `## Consequences` sections present.
- **Content completeness (AC-mapped):**
  - States the chosen substrate (shell drain+poll loop invoking the ADR-0024 executor per Issue, ~5-min idle cadence). — AC#2
  - Lists **cron**, **`/loop`+`/routines`**, **Workflow engine** each with a rejection reason. — AC#2
  - Records v1 limits: **serial**, **synchronous drain**, **idle-poll (not process-exit) quiescence**; **cross-references ADR-0024**. — AC#3
  - No dangling "deferred"/"`/plan`-phase" substrate pointer remains in PRD / CONTEXT.md / ADR-0024 (all point to ADR-0026). — AC#4
- **zh summary:** PR body carries `## 變更說明` (authored by `/validate` Phase 5; ADR-0022). — AC#5
- **E2E grep proof:** `grep -rniE "runtime substrate.*(/plan|deferr)|deferred to #63" docs/ .agents/prds/ CONTEXT.md` returns no bare dangling pointer (every hit references ADR-0026, except ADR-0024's Status annotation which *is* the pointer).

## Acceptance Criteria
- [ ] `docs/adr/0026-…md` created — next sequential number, repo ADR format (AC#1)
- [ ] States chosen substrate + lists cron / `/loop`+`/routines` / Workflow engine with a rejection reason each (AC#2)
- [ ] Records v1 limits (serial, synchronous drain, idle-poll quiescence) + cross-references ADR-0024 (AC#3)
- [ ] Linked from the PRD (further-notes + both deferral spots) and CONTEXT.md; ADR-0024 Status-line forward pointer added — no dangling "deferred" pointer remains (AC#4)
- [ ] PR body carries the Traditional Chinese `## 變更說明` (AC#5, ADR-0022) — handled at `/validate` Phase 5
- [ ] `bash .claude/validate.sh` exits 0
- [ ] Canonical docs (ADR, CONTEXT.md) stay English; ADR-0024 body unchanged (append-only)
- [ ] Every external-behavior claim VERIFIED by a probe or source-read (see Assumptions & Risks)
