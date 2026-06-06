# PRD — PIV Pipeline Automation (stateless `claude -p` driver)

Status: ready-for-agent
Source decisions: ADR-0008 (and CLAUDE.md: Smart Zone, PIV Loop, System Evolution)

## Problem Statement

This repository **documents** the PIV Loop (Plan → Implement → Validate, each a fresh
session) as a discipline a human enacts by hand: open a clean session, load the ticket, do
one phase, `/clear`, repeat — per phase, per ticket. ADR-0008 settled the *shape* of
automating that loop (a stateless `claude -p` bash driver, files as the only interface,
fail-fast with a restrained retry, a human merge gate, worktrees/cron explicitly rejected),
but **nothing implements it**.

The cost of the gap is that the Smart Zone discipline currently depends on a human
remembering not to pollute context. There is no artifact that externalizes ticket order and
inter-phase state to files, no guarantee each phase actually starts fresh, and no mechanical
place where a failure becomes a System Evolution signal. A solo developer hand-drives every
phase and, the moment they get lazy and "just continue in the same session," recreates
exactly the dumb-zone accumulation the whole design exists to prevent.

## Solution

Build a **stateless bash driver**, `scripts/run-piv.sh`, that runs a project's Tickets
through the PIV Loop with no brain outliving a single job.

From the developer's perspective, after this ships:

- They run `scripts/run-piv.sh` (optionally scoped to specific Ticket ids). It reads the
  Tickets under `.agents/tickets/`, orders them by their `blocked_by` frontmatter, and for
  each Ticket fires **three separate `claude -p` invocations** — Plan, Implement, Validate —
  each a fresh process with zero memory of the prior phase. State passes **only through
  files**: Plan writes `.agents/plans/{slug}.plan.md`; Implement and Validate read it back.
- Each phase **loads this repo's CLAUDE.md** (the AI Layer contract) — the driver does
  **not** use `--bare`, so every memoryless process still knows the house rules.
- On a **red** phase (non-zero exit): a machine-decidable failure (lint/type, identified by
  the project's Verify commands) is retried **once**; anything else writes `.agents/FAILED.md`
  and **stops the line**. The stop is framed as a System Evolution signal: "why was this plan
  not good enough to run unattended?"
- On a Ticket going **all green**: the driver commits to a per-Ticket branch and **stops at
  "PR awaiting review"** — it never auto-merges. The human does the one low-cost, high-leverage
  yes/no at the merge gate.
- `--dry-run` prints the exact ordered plan of phase invocations and mutates nothing.

Worktrees, cron/Routines, and `/loop` are deliberately **not** used (ADR-0008): independence
comes from memoryless `claude -p` processes, ordering from the driver's Ticket list, and the
contract from a lean CLAUDE.md.

## User Stories

1. As a solo developer, I want a `run-piv.sh` driver that runs my Tickets through Plan →
   Implement → Validate automatically, so that I stop hand-driving every phase.
2. As a developer, I want each phase to be a **separate `claude -p` process**, so that no
   phase carries context residue from the previous one (Smart Zone).
3. As a developer, I want **all inter-phase state to live in files** (`.agents/plans/{slug}.plan.md`
   and the Ticket file), so that the driver itself holds no memory and never degrades.
4. As a developer, I want the Plan phase to write `.agents/plans/{slug}.plan.md` and the later
   phases to read it, so that the plan file is the only Plan→Implement interface (PIV Loop).
5. As a developer, I want each phase to **load CLAUDE.md** (not run `--bare`), so that every
   memoryless process still obeys the AI Layer contract.
6. As a developer, I want the driver to **order Tickets by their `blocked_by` frontmatter**,
   so that dependencies are honored without me maintaining a separate index.
7. As a developer, I want to optionally pass specific Ticket ids to run, so that I can drive a
   subset instead of the whole backlog.
8. As a developer, I want a phase's **non-zero exit to stop the line by default** (fail-fast),
   so that broken state is never accumulated or committed (CLAUDE.md: never accumulate broken
   state).
9. As a developer, I want a **machine-decidable failure (lint/type) retried exactly once**
   before stopping, so that trivially-fixable reds don't need me but ambiguous ones do.
10. As a developer, I want any other (non-machine-decidable) failure to **write `.agents/FAILED.md`
    and stop**, so that I have a precise, file-based record of where and why the line stopped.
11. As a developer, I want `FAILED.md` to name the Ticket, the phase, the failing command, and
    its output, so that I can intervene without re-deriving context.
12. As a developer, I want the failure handoff to **explicitly point at the System Evolution
    loop**, so that each stop becomes an opportunity to improve the AI Layer, not just a patch.
13. As a developer, I want a Ticket that goes all-green to be **committed to a per-Ticket
    branch**, so that work is isolated per Ticket without me managing branches by hand.
14. As a developer, I want the driver to **stop at "PR awaiting review" and never auto-merge**,
    so that a human keeps the final yes/no at the merge gate (ADR-0008).
15. As a developer, I want `run-piv.sh --dry-run` to print the exact ordered phase plan and
    mutate nothing, so that I can preview a run before it touches anything.
16. As a developer, I want the driver to be **idempotent-friendly** — skipping Tickets already
    at "PR awaiting review" / merged — so that re-running after an intervention resumes cleanly.
17. As a developer reviewing the change, I want the driver's behavior covered by an
    **executable test** that uses a stubbed `claude`, so that validation burns no tokens and is
    a real gate (executable, not prose).

## Implementation Decisions

**Modules built/modified**

- **`scripts/run-piv.sh`** (new). A stateless bash driver. Responsibilities:
  - **Ticket discovery + ordering.** Reads `.agents/tickets/*.md`, parses `id` and `blocked_by`
    from frontmatter, and produces a dependency-respecting order (topological by `blocked_by`).
    Optional positional args narrow the run to specific ids (their unmet dependencies still run
    first or block).
  - **Per-phase invocation.** For each Ticket, three sequential `claude -p` calls — Plan,
    Implement, Validate — each a fresh process. Phase prompts are short and reference files, not
    inline state. The driver does **not** pass `--bare` (CLAUDE.md must load); it passes
    `--allowedTools` / `--permission-mode` so headless runs don't block on prompts.
  - **State contract.** Plan writes `.agents/plans/{slug}.plan.md`. Implement reads the plan,
    edits code, runs the project's Verify commands. Validate reads the plan and re-runs the
    Verify commands. Nothing passes between phases except files.
  - **Exit-code contract.** Each phase's success is the **exit code of the project's Verify
    commands**, not the model's prose. A phase is red iff a Verify command exits non-zero.
  - **Retry policy.** A red phase is retried **once** iff the failure is *machine-decidable* —
    defined as the lint/type Verify commands failing (their fixes are mechanical). Test/E2E/
    behavioral reds are **not** retried; they stop the line. (The exact machine-decidable set is
    read from CLAUDE.md "Verify commands" / project config; default to lint + type-check.)
  - **Failure handoff.** On a stop, write `.agents/FAILED.md` with Ticket id+slug, phase,
    failing command, captured output, and a fixed pointer to the System Evolution loop. Exit
    non-zero.
  - **Green handoff.** On all-green for a Ticket: commit to branch `piv/{NN}-{slug}` and stop at
    "PR awaiting review" (record state; do **not** merge, do **not** open the next Ticket's merge
    without that one's gate — but *may* continue running independent later Tickets, per ordering).
  - **`--dry-run`.** Print the ordered list of `(ticket, phase, command)` it would run; mutate
    nothing. Mirror the `[piv] would …` line style used by the repo's other scripts.

- **Phase prompt templates** — inlined in `run-piv.sh` (kept terse; they reference the ticket
  file and plan file by path rather than embedding content).

**Contract boundaries (ADR-0008)**

- No worktrees in the default flow — serial execution needs no disk isolation; worktrees are a
  future parallelism affordance only.
- No cron/Routines/`/loop` — the driver is invoked directly; a timer (if ever wanted) wraps the
  driver from outside.
- No auto-merge — green stops at the human PR gate.

## Testing Decisions

Assert **external behavior at the highest seam**: the driver's observable plan and its
file/git effects, never internal bash functions. The driver shells out to `claude` and to the
project Verify commands — both are stubbed so tests are hermetic and burn no tokens.

- **`scripts/run-piv.test.sh`** (new, self-contained bash; no external framework — CLAUDE.md
  forbids stack-specific tooling). Runnable as `bash scripts/run-piv.test.sh`, exits non-zero on
  any failed assertion, and is this feature's PIV **validate gate** (gates must be executable).
- **Stubbing.** A fixture `claude` shim earlier on `PATH` records its args and emits canned
  outputs / exit codes per scenario; a fixture Verify command lets a test force a given phase
  red or green. Tests run against fixture `.agents/tickets/` and a throwaway git repo / temp
  `.agents/`, leaving no residue.
- **Cases to cover:**
  - (a) **Ordering** — Tickets with `blocked_by` are planned in dependency order; `--dry-run`
    prints that order and mutates nothing.
  - (b) **Fresh-process contract** — three separate `claude -p` invocations per Ticket, none
    passed `--bare`, plan written to `.agents/plans/{slug}.plan.md` and read by later phases.
  - (c) **Fail-fast** — a non-machine-decidable red (test/E2E) writes `.agents/FAILED.md` with
    Ticket/phase/command/output + System Evolution pointer, and the driver exits non-zero
    without committing.
  - (d) **Retry-once** — a lint/type red is retried exactly once; a second red then stops the
    line; a test/E2E red is **never** retried.
  - (e) **Green gate** — an all-green Ticket commits to `piv/{NN}-{slug}` and stops at "PR
    awaiting review"; no merge occurs.
  - (f) **Resume** — re-running skips Tickets already at "PR awaiting review" / merged.

## Out of Scope

- **Parallel execution / worktrees** — serial only; worktrees are a future affordance (ADR-0008).
- **Cron / Routines / `/loop` triggering** — the driver runs on demand; any timer wraps it
  externally (ADR-0008).
- **Auto-merge** — green always stops at the human PR gate (ADR-0008).
- **Pushing Tickets/PRDs to an external tracker** — this repo has no remote; artifacts are files
  (consistent with the Phase 1 machinery PRD).
- **Calling the real `claude` binary in tests** — tests use a `claude` stub; real end-to-end
  behavior is verified manually on first run.
- **The multi-repo control plane / orchestrator** — separate later project (ADR-0003).

## Further Notes

- **Recursion, acknowledged.** This feature is the AI Layer building the machine that drives the
  AI Layer. The first real run of `run-piv.sh` can legitimately be driven *over these very
  Tickets* as its own dogfooding test.
- **Verify commands are the source of truth for red/green.** They live in CLAUDE.md "Project
  specifics → Verify commands"; this driver consumes them and does not hardcode any stack tool.
- **Suggested Ticket slicing** (tracer-bullet, confirm at decomposition): (05) driver skeleton —
  discovery + `blocked_by` ordering + `--dry-run` plan + tests; (06) real per-phase `claude -p`
  execution with CLAUDE.md loaded and file-based state; (07) failure handling — fail-fast +
  retry-once + `FAILED.md` + System Evolution pointer; (08) green path — per-Ticket branch commit
  + stop at PR gate + resume. Slices 05–07 are AFK; 08 is HITL (git/merge policy review).
