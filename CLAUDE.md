# CLAUDE.md

This file is the **AI Layer** for this project: the always-loaded contract that tells
Claude how to think, work, and verify here. Keep it lean (aim for under ~2.5k tokens); a bloated system
prompt starts every session already degraded.

Replace the bracketed placeholders with project-specific values. Delete sections that do
not apply. Do not add stack-specific tooling to this template — keep it language-agnostic
and let each project fill in its own commands.

---

## Smart Zone

LLMs have two hard limits this project is designed around:

1. **Context decay** — an agent does its best work in roughly the first ~100k tokens of a
   session. Past that, attention relationships overload and decisions get sloppy. A larger
   context window does not fix this; it only buys more *dumb zone*.
2. **Amnesia** — clearing context resets the agent entirely. Nothing survives a session
   except what was written to a file.

The working rules that follow from this:

- **One job per session.** Plan, implement, and review are separate sessions (see
  [PIV Loop](#piv-loop)). Don't review code in the same session that wrote it — the
  reviewer would be a dumber version of the implementer.
- **Prefer `/clear` over compaction.** Clearing returns you to a known baseline. Compaction
  leaves sediment that destabilizes later behavior. Re-prime from files instead.
- **Offload research to sub-agents.** Codebase exploration can burn hundreds of thousands
  of tokens. Delegate it; pull back only the summary so the main context stays in the
  smart zone.
- **Files are the only durable memory.** The handoff between sessions is a written
  artifact (a plan, a report), never the agent's recollection.
- **Watch your own budget.** If a task is pushing you past the smart zone mid-build, write
  a checkpoint file describing remaining work and stop cleanly rather than degrading.

## PIV Loop

The per-task inner loop: **Plan → Implement → Validate**. Each phase is a *fresh session*;
the plan file is the only interface between Plan and Implement. This separation is
deliberate — it stops planning bias and context pollution from leaking into implementation.

1. **Plan** (`/plan`) — New session. Load the Issue plus the relevant slice of the
   codebase, explore (delegate heavy research to sub-agents), and emit a context-rich
   plan to `.agents/plans/{name}.plan.md`. No code is written. The plan names the exact
   `file:line` patterns to mirror, the files to change, an ordered task list, and the
   validation strategy.
2. **Implement** (`/implement`) — **Reopen a fresh session.** Read the plan, verify its
   assumptions against the real code, then execute task by task. Run the project's checks
   after every task and fix failures before moving on — never accumulate broken state.
3. **Validate** (`/validate`) — **Own fresh session.** Runs the full gate (`validate.sh` +
   the plan's E2E checklist), then hands to human review. Pass → merge. Problem →
   drop into the [System Evolution](#system-evolution) outer loop via `/retroactive`.

Anytime you find yourself prompting the same thing more than three times, promote it to a
command or skill.

## System Evolution

The outer loop. When a PIV Loop surfaces a bug or a miss, don't just patch the surface
code — treat it as a signal that the **AI Layer itself** is incomplete. Run a *retroactive
session*:

> "You let this problem reach the codebase. Look at your AI Layer — the rules, commands,
> skills, and workflow — and find what we can change so this class of problem can't recur."

Four places to look:

1. **Commands** — is the procedure itself missing a step? (e.g. a check the validate flow
   should always run)
2. **On-demand context** — do `examples/` or referenced docs need updating?
3. **Global rules** (this file) — is an existing constraint too vague to bind?
4. **Plan / PRD templates** — is a section structurally missing?

## Conventions

Behavioral guardrails for every change. These bias toward caution over speed; for trivial
tasks, use judgment.

**Think before coding.** State assumptions explicitly; if uncertain, ask. If multiple
interpretations exist, surface them all — don't silently pick one. If something is unclear,
stop and name what's confusing.

**Simplicity first.** Write the minimum code that solves the problem. No speculative
features, no abstractions for single-use code, no error handling for impossible scenarios.
If 200 lines could be 50, rewrite it.

**Surgical changes.** Touch only what the task requires. Don't "improve" adjacent code or
reformat unrelated lines. Match existing style. Remove only the orphans *your* change
created; leave pre-existing dead code (mention it instead). Every changed line should trace
to the request.

**Goal-driven execution.** Turn each task into a verifiable success criterion before
starting — "add validation" becomes "write tests for invalid inputs, then make them pass."
Strong criteria let the agent loop independently; weak ones ("make it work") force constant
clarification.

**Verification-led.** Rate of feedback is your speed limit. Define how you'll verify work
*before* doing it. Prefer test-driven, vertical tracer-bullet slices (one test → one
implementation → repeat) over writing all tests up front. See
[`.claude/skills/tdd-gate/SKILL.md`](.claude/skills/tdd-gate/SKILL.md) and
[`examples/deep-module-pattern.md`](examples/deep-module-pattern.md).
Each project bundles its verify commands into `.claude/validate.sh`; the global
`validate_gate` `Stop` hook runs it automatically on session end (fails open when absent).

---

### Project specifics

Fill these in per project. Keep it short.

- **Stack**: [language, framework, key libraries]
- **Verify commands**: [the project's lint / type-check / test / build commands]
- **Architecture**: [e.g. vertical slices under `src/features/`; one folder owns a feature
  end-to-end so an agent reads one place, not every layer]
- **Do-not**: [project-specific footguns the agent keeps hitting — add to this list
  whenever a retroactive session finds one]
