# Night Shift recurring-invocation substrate is a shell drain+poll loop, not cron / `/loop` / a Workflow engine

**Status:** Accepted (2026-07-02); relates to the Night Shift PRD
(`.agents/prds/piv-ralph-loop.prd.md`, #63/#81); **resolves the recurring event+poll scheduler
substrate deferred by ADR-0024 §3**; builds on ADR-0024 (executor substrate, headless `claude -p`
in its own clone) and ADR-0023 (triggers schedule, don't judge).

## Context

Two distinct "substrate" questions sit under the Night Shift, and only one had been recorded.

ADR-0024 fixed the **executor substrate**: *how each phase runs* — one headless `claude -p "/<phase>"`
subprocess per phase, in the Night Shift's own clone. Its §3 explicitly **deferred** the
**recurring-invocation substrate**: *how the executor is invoked repeatedly* — the event channel
plus scheduling poll, queue selection across many Issues, the serial→N concurrency dial, and the
kill switch. That was left "to #63."

The PRD (`.agents/prds/piv-ralph-loop.prd.md:156-158`, `:248-249`) named this a `/plan`-phase
decision and deliberately fixed only *behavior* — a **hybrid trigger**: event-driven on the happy
path, with a ~5-minute poll as the safety net that discovers newly-ready Issues and recovers any
dropped completion event. It listed three candidate substrates without choosing (cron /
`/loop`+`/routines` / a Workflow engine).

#81 then **shipped** the substrate (`scripts/night_shift_loop.sh`, closing #63) — but with no
companion ADR. The decision lived only implicitly, in the script and the #81 PR body. This ADR
records it so the deferred thread has a durable, findable answer.

## Decision

The recurring-invocation substrate is a **plain Bash outer loop** (`scripts/night_shift_loop.sh`),
grounded in that script:

1. **A thin selection wrapper, not an orchestrator.** The loop runs in the Night Shift's own clone
   (ADR-0024) and holds **no phase logic**: it only `select`s the next grabbable Issue and hands it
   to the executor (`night_shift_run.sh`), which owns the claim and the phase-chaining. The per-phase
   `claude -p` substrate stays ADR-0024's. (`night_shift_loop.sh:1-9`, `select_issue:60-72`.)

2. **Hybrid cadence realized as drain-then-poll.** `drain()` runs Issues back-to-back with **zero
   idle wait** while the ready set is non-empty — the event-driven happy path. `loop()` sleeps
   `NIGHT_SHIFT_POLL_INTERVAL` (**default 300s ≈ 5 min**) only when a drain pass finds nothing — the
   safety-net poll that re-discovers newly-ready Issues and recovers dropped completions.
   (`drain:87-116`, `loop:118-136`, interval default `:24`/`:38`.)

3. **Level-triggered on durable artifact state**, not an async event bus. Selection reads the
   executor's side-effects — the `in-progress` claim label, and `PR_OPEN`/`ESCALATED` from
   `snapshot` — so the loop is restartable and idempotent (consistent with ADR-0023's pure-state
   decider). A **no-progress guard** ends the pass if the same Issue re-selects after dispatch,
   backing a hot-spin off to the poll interval instead of re-running its full PIV cycle with zero
   wait. (`select_issue:60-72`, `_terminal_for:56-58`, `drain:97-107`.)

4. **Serial v1.** `NIGHT_SHIFT_CONCURRENCY` defaults to 1; `_require_serial` rejects any other value
   with `rc 2` before any `gh`/executor call — N is a reserved graduation, not a supported mode.
   (`_require_serial:76-81`, `drain:88`, `loop:119`.)

5. **Kill switch = file sentinel *and* signal trap.** A `.night-shift/stop` file (`_stopped`) checked
   each iteration, plus an `INT`/`TERM` trap in `loop()`. Either stops the loop cleanly.
   (`_stopped:83`, `drain:91`, `loop:120`,`:123`.)

6. **DI seams make it offline-testable.** `gh`, the executor (`RUN`), and `sleep` are all
   dependency-injected, so the loop is exhaustively unit-tested with **zero credit spend**
   (`scripts/night_shift_loop.test.sh`). (`night_shift_loop.sh:17-28`.)

## Why this over the alternatives

Chosen for v1 on **simplicity-first** (CLAUDE.md): the outer loop is a thin selection wrapper that
reuses ADR-0024's `claude -p` substrate with **zero new runtime dependency** — in-repo,
committable, offline-testable, and level-triggered (so restartable). The executor already owns
claim + phase-chaining + terminal state, so a shell `while` + `select` + `sleep` is the minimum
that works. The three candidates the PRD named (`:156-158`, `:248-249`):

- **cron** — rejected: an external scheduler, with nothing in-repo to commit or test; fixed-interval
  only, so it cannot do the event-driven back-to-back drain (it either adds latency or hammers the
  API), and it addresses neither selection nor the claim. (Mirrors ADR-0024's cron rejection.)

- **`/loop` + `/routines`** — rejected: a long-lived self-reprompting **claude session** as the
  scheduler costs credits merely to *wait*, is not testable offline, and blurs the very isolation
  boundary the design protects (per-phase fresh sessions — ADR-0023/0024). The PRD put it out of
  scope.

- **Workflow engine / subagents** — rejected: more orchestration machinery than a level-triggered
  selector needs, and a subagent is not a full PIV session — it does not expand the project slash
  command or load the session hooks (ADR-0024), so it cannot faithfully *be* `/plan` / `/implement`
  / `/validate`.

## Consequences

Known limits, stated plainly (all v1):

- **Serial only** — concurrency is 1; N is a reserved graduation (the `piv-loop`
  parallel-implement / serial-landing protocol is the intended path).
- **Synchronous drain** — the loop **blocks** on each `"$RUN" "$n"`; one slow task stalls the whole
  queue behind it.
- **Quiescence is idle-poll, not process-exit** — the loop is a **persistent process**; a drained
  queue means *sleep*, not exit (only the kill switch or `MAX_POLLS` stops it). "Idle" ≠ "done."
- **"Event-driven" is level-triggered re-selection**, not a webhook or event channel; a dropped
  completion is recovered by the **next poll**, not by an interrupt.
- A future move to a different substrate (cron / a Workflow engine / a long-lived session) is a
  **reversal** of this ADR and must be recorded as a superseding one.
