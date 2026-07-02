# Night Shift triggers schedule phases; they never judge semantic completion

**Status:** Accepted (2026-06-28); **sharpens ADR-0010** (System Evolution triggered by handoff,
not hook). Relates to the Night Shift PRD (`.agents/prds/piv-ralph-loop.prd.md`) and the CLAUDE.md
Smart Zone / PIV Loop doctrine.

## Context

The **Night Shift** (see `CONTEXT.md`) drives each `ready`-labelled Issue through the whole PIV
Loop with no human between phases: a finished `/plan` triggers `/implement`, a finished
`/implement` triggers `/validate`, and a **scheduling poll** backstops that synchronous trigger
chain. These
are all *mechanical* triggers.

ADR-0010 drew a general rule — **"hooks enforce objective red/green floors; handoffs carry semantic
flow"** — and used it to argue that System Evolution must be triggered by a workflow handoff, not a
lifecycle hook, because "did a defect of some class escape?" is a semantic judgment a mechanical
hook cannot make.

On its face the Night Shift contradicts that rule: it uses mechanical triggers to advance the
loop, which looks like driving *semantic flow* with a *hook*. Left unsharpened, a future reader (or
implementer) reads the two as in conflict and "resolves" it the wrong way — either weakening
session isolation ("the loop may as well judge completion inline and skip the fresh session") or
distrusting the mechanical triggers altogether.

## Decision

A mechanical trigger in the Night Shift may **schedule** a phase but must **never judge** semantic
completion.

- **Schedule (mechanical, allowed):** decide *which phase runs next* purely from objective, durable
  artifact state — is the plan file present? the report? is the validate gate green? what is the
  attempt count? This is the pure next-action decider; it reads *facts*, not *quality*.
- **Judge (semantic, forbidden to the trigger):** decide whether the work is actually correct or
  done. That judgment stays *inside* the phase, carried by two artifacts: the **report** (the
  implement step's semantic record of what was done) and the **validate gate** verdict (the
  objective red/green floor). The trigger consumes those artifacts' *existence and verdict*; it
  never forms the judgment itself.

This adds a third row to ADR-0010's taxonomy:

| mechanism | role |
|---|---|
| hook | enforce an objective red/green floor |
| handoff | carry semantic flow (a human/agent judgment crosses sessions) |
| **mechanical scheduler** | **advance the loop by objective artifact state — never judge semantic completion** |

The scheduler is hook-like (mechanical, objective) but its output is "run the next phase," not "a
floor passed/failed." The semantic judgment ADR-0010 reserved for handoffs is untouched: the Night
Shift never mechanically decides "this plan is good" or "a bug escaped." A red gate (objective)
routes to the retry ladder; escalation fires at an objective attempt count K — never on a *judged*
verdict.

## Why this over the alternatives

- **Let the trigger judge completion** (a long-lived loop that inspects output and decides "looks
  done, move on") — rejected: that is the naive **Ralph Loop**. It collapses per-phase session
  isolation (CLAUDE.md Smart Zone) and re-introduces exactly the semantic-judgment-by-machine
  ADR-0010 forbids. The Night Shift's entire purpose is to keep isolation *while* removing
  orchestration friction.
- **Fold this into ADR-0010 as a revision** — rejected: ADR-0010's decision (System Evolution's
  trigger) is unchanged. This is a new distinction born of a new context (the Night Shift).
  Overloading one ADR with two decisions erodes the append-only, one-decision-per-ADR history.
- **Leave the apparent contradiction undocumented** — rejected: the Night Shift's mechanical
  triggers visibly resemble the hook ADR-0010 rejected; an unexplained tension invites an
  implementer to "simplify" by letting the loop judge inline.

## Consequences

- The next-action decider is a **pure function of objective artifact state** — exhaustively
  testable offline (the PRD's main test seam) *because* it judges nothing.
- Loop correctness never depends on an agent's in-session judgment of "is this done"; it depends
  only on artifacts that survive a restart, so the loop is restartable and idempotent on identical
  state.
- Session isolation per phase is reinforced as an invariant: since the trigger may not judge, each
  phase must write its own judgment to its artifacts (report, gate verdict) before exiting — there
  is nowhere else for that judgment to live.
- A future change that wants the loop to skip a phase "because it looks unnecessary," or to advance
  on a heuristic rather than on artifact presence, is a *reversal* of this ADR and must be recorded
  as a superseding one.
