---
id: "07"
slug: run-piv-failure-handling-system-evolution
title: Failure handling — fail-fast + retry-once + FAILED.md + System Evolution pointer
type: AFK
status: ready-for-agent
blocked_by: ["06"]
prd: .agents/prds/piv-pipeline-automation.prd.md
covers_stories: [9, 10, 11, 12]
---

# Failure handling — fail-fast, restrained retry, System Evolution handoff

## What to build

Turn the bare "red phase aborts" propagation (Ticket 06) into the ADR-0008 failure policy:
fail-fast by default, a single restrained retry only for machine-decidable failures, and a
file-based handoff that explicitly feeds the System Evolution outer loop.

In `scripts/run-piv.sh`:

- **Fail-fast default.** Any red phase stops the line — the driver does not proceed to the next
  phase or commit broken state (CLAUDE.md: never accumulate broken state).
- **Retry-once, machine-decidable only.** A red phase is retried **exactly once** iff the
  failure is *machine-decidable* — defined as the **lint and/or type-check** Verify commands
  failing (their fixes are mechanical). The retry re-runs that same phase as a fresh
  `claude -p`. If it is still red after the single retry, stop the line.
- **Never retry behavioral reds.** Test / E2E / behavioral Verify failures are **not**
  machine-decidable and are **never** retried — they stop the line on the first red.
- **`FAILED.md`.** On a stop, write `.agents/FAILED.md` containing: Ticket id + slug, the phase
  (Plan/Implement/Validate), the failing Verify command, its captured stdout/stderr, whether a
  retry was attempted, and a **fixed pointer to the System Evolution loop** — the prompt
  "You let this problem reach the line. Look at your AI Layer — rules, commands, skills,
  workflow — and find what change stops this class of problem recurring" (CLAUDE.md System
  Evolution). Exit non-zero.
- **Which Verify commands are machine-decidable** is derived from CLAUDE.md "Project specifics
  → Verify commands" (lint + type-check), not hardcoded per stack; default to treating only
  lint/type as machine-decidable if the project does not classify them.

## Acceptance criteria

- [ ] A lint/type red is retried **exactly once**; a still-red second attempt stops the line.
- [ ] A test/E2E/behavioral red is **never** retried and stops on the first red.
- [ ] On any stop, `.agents/FAILED.md` is written with Ticket id+slug, phase, failing command,
      captured output, retry-attempted flag, and the System Evolution pointer; the driver exits
      non-zero.
- [ ] No commit is produced when the line stops.
- [ ] `scripts/run-piv.test.sh` is extended (still the validate gate) with cases driven by the
      `claude` stub + stub Verify command: (a) lint/type red → retried once; (b) lint/type red
      twice → stop + FAILED.md; (c) test/E2E red → stop immediately, no retry; (d) FAILED.md
      content includes all required fields + the System Evolution pointer.

## Blocked by

Ticket 06 (needs real per-phase execution and the Verify-exit-code red/green contract to fail
against).

## Notes

The point of the policy (ADR-0008): the goal is **not** zero intervention. A stop is a signal —
every `FAILED.md` is an invitation into the System Evolution loop to ask "why was this plan not
good enough to run unattended?" and improve the plan template / commands so the class of failure
can't recur. Keep the restrained retry genuinely restrained: only mechanical, machine-decidable
failures, only once. Letting a memoryless brain auto-retry things it doesn't understand burns
tokens and drifts the code — that path is explicitly rejected.
