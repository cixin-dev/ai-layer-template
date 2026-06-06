# PIV pipeline is driven by a stateless `claude -p` loop, not worktrees or cron

A recurring instinct is that Claude Code's **worktree** command is the engine for running
tickets "independently" — that you arrange tickets in order and worktrees run each one in
isolation. This conflates three separate concerns onto one tool that owns none of them.
Worktrees provide *git/filesystem isolation* (a separate working copy + branch so parallel
agents don't stomp each other). They do **not** sequence tickets, do **not** resolve
dependencies, and do **not** merge results back. And critically, the pollution this AI Layer
actually fears is *context* pollution (a single brain carrying residue across jobs — see
Smart Zone in CLAUDE.md), which worktrees do nothing about: they give you a clean *disk* and
the *same* dirty *brain*.

**Decision:** automate the PIV Loop with a **stateless bash loop calling `claude -p`**, one
fresh invocation per phase, with all state externalized to files.

```
for ticket in <ordered ticket list>:
    claude -p "Plan: read ticket → write .agents/plans/{t}.plan.md"   # fresh context
    claude -p "Implement: read plan → execute → run checks"           # fresh context
    claude -p "Validate: read plan → lint/type/test/e2e"              # fresh context
    ├─ green → commit to ticket branch, stop at "PR awaiting review" (human merge gate)
    └─ red   → machine-decidable failures (lint/type) retry once;
               else write .agents/FAILED.md and stop the line
               └─ human intervention = enter the System Evolution outer loop
```

The three concerns map to tools that are **not** worktree:
- **"Independent operation"** → each `claude -p` is a memoryless process: fresh context, zero
  recollection of the prior phase. Files are the only interface.
- **"Arrange the order"** → the bash script's ticket list; ordering and dependencies are the
  script author's responsibility.
- **A clean brain that still knows the house rules** → load a lean CLAUDE.md each phase
  (do **not** use `--bare`, which skips CLAUDE.md / hooks / skills / MCP). Loading the contract
  is cheap because it is deliberately kept under ~2.5k tokens.

**Failure is a signal, not just a stop.** Fail-fast is primary; a single retry is allowed only
for machine-decidable failures (lint autofix, type errors). Every other stop hands off to a
human and feeds the System Evolution outer loop: "why was this plan not good enough to run
unattended?" → improve the plan template / commands. The goal is not zero intervention; it is
that each intervention upgrades the system.

**Green still gates on a human.** Phases run to green-and-reviewable; the machine commits to the
ticket branch but does not auto-merge. A human does the low-cost, high-leverage yes/no at the PR
gate — consistent with CLAUDE.md's "Pass → merge" plus human review.

Alternatives rejected:
- **Worktrees as the driver**: they are isolation padding, not an engine, and address disk
  pollution this serial pipeline doesn't have. Reach for them only if/when truly *parallel*
  independent tickets are wanted — and the real cost then is merge conflicts, not worktrees.
- **Cron / Routines (`/schedule`)**: cloud-run, 1-hour minimum granularity, Pro+ only —
  overkill for chaining phases. Wrap cron *outside* the loop only to trigger a whole batch on a
  timer.
- **`/loop`**: requires a long-lived open session, violating the "no brain outlives one job"
  rule.
- **A main orchestrating session spawning sub-agents**: viable as a lightweight variant while
  the smart zone holds, but the orchestrator accumulates summaries/decisions per ticket and
  degrades as ticket count grows — it dilutes pollution rather than eliminating it.

Consequence: no brain outlives a single job; sequence and state live entirely in files; the
driver itself is dumb and memoryless, so it never degrades. Worktrees stay out of the default
flow as a future parallelism affordance, not the mechanism.
