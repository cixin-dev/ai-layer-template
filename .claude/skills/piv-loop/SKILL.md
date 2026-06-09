---
name: piv-loop
description: The Plan-Implement-Validate inner loop for working one Issue at a time. Use when starting a feature or bug fix, when deciding how to structure a multi-step task, or when the user mentions PIV, plan/implement/validate, or session separation.
---

# PIV Loop

Plan → Implement → Validate. The per-Issue inner loop of agentic engineering. Its defining
move is **session separation**: each phase runs in its own fresh session, and a written
file is the only thing that crosses between them.

## Why session separation

An agent works best in the first ~100k tokens (the smart zone). A single session that
plans, implements, *and* reviews accumulates bias and sediment — by review time the agent
is a dumber version of the one that planned. Splitting phases keeps each one starting from a
known baseline. The cost (re-priming from a file) is deliberate; it's what buys the
quality.

## The three phases

**Plan** — New session. Load the Issue and the relevant codebase slice. Explore, pushing
heavy research to sub-agents so the main context stays lean. Emit
`.agents/plans/{name}.plan.md` with: user story, patterns to follow (real `file:line`
snippets), files to change, an ordered task list, and the validation strategy. No code.
→ run `/plan`.

**Implement** — **Reopen a fresh session.** The plan file is the entire handoff. Verify the
plan's assumptions against real code, then execute task by task, validating after each one
and fixing failures before proceeding.
→ run `/implement <plan-path>`.

**Validate** — **Fresh session.** Run the full gate (`validate.sh` + the plan's E2E
checklist), then hand to human review. Pass → merge. Problem → deterministic handoff to
[`/retroactive`](../system-evolution/SKILL.md) in a fresh session (the System Evolution
trigger — workflow-routed, not a hook).
→ run `/validate <plan-path>`.

## Rules

- One job per session; prefer `/clear` over compaction between phases.
- The plan file is the contract — if it's wrong, fix it (or adapt and document), don't
  silently diverge.
- Never carry broken state forward between tasks.
- Promote anything you prompt more than three times into a command or skill.

## When NOT to use

Trivial one-line changes don't need the full loop — use judgment. The ceremony pays off for
anything with real design surface or more than a couple of steps.
