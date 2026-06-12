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
checklist), then hand to human review. Pass → push + open PR → merge → run
`/finish {branch}`. Problem → deterministic handoff to
[`/retroactive`](../system-evolution/SKILL.md) in a fresh session (the System Evolution
trigger — workflow-routed, not a hook).
→ run `/validate <plan-path>`.

## Rules

- One job per session; prefer `/clear` over compaction between phases.
- The plan file is the contract — if it's wrong, fix it (or adapt and document), don't
  silently diverge.
- Never carry broken state forward between tasks.
- Promote anything you prompt more than three times into a command or skill.

## Parallel implement

Run several Issues' `/implement` sessions concurrently and land them safely.

**Precondition** — each Issue has its own human-reviewed plan from the normal `/plan` flow.
Parallelism starts from N already-reviewed plans, not N raw Issues.

**Pre-flight check** — before opening parallel sessions, verify two concrete inputs:
- GitHub **`Blocked by #NN`** dependency links between the Issues — any blocker link means
  those plans must run serially.
- Pairwise intersection of each plan's **"Files to Change"** table — any shared file means
  those plans must run serially.

**Carrier** — one real interactive terminal session per plan (tmux panes or terminal tabs),
each running `/implement <plan>`. Worktree isolation comes from `/implement` Phase 2's
existing convention (one worktree per branch); do not re-specify it here. Blockers are
resolved by asking the human directly, not by an agent.

Sub-agents are **not** the carrier. Three reasons:
1. Background sub-agents are effectively read-only — Write, Bash, and `gh` are auto-denied,
   so a sub-agent cannot run the mutating steps of `/implement` (branch, commit, PR).
2. The Agent tool snapshots from session-start HEAD — a plan file committed mid-session
   (exactly what `/implement` Phase 2 does, per ADR-0014) is invisible to a sub-agent
   spawned after that commit.
3. No Stop-hook gate for sub-agents — the `validate_gate` Stop hook runs on session end,
   not sub-agent end, so a sub-agent carrier would bypass the only hook-enforced validation
   floor (see ADR-0009).

**Serial landing** — implements may run in parallel, but landing is one branch at a time.
For each branch, in order:
1. `git merge origin/main` inside the worktree — picks up already-merged siblings; semantic
   conflicts surface here.
2. `/validate` — validates the *combined* state (the branch as it will actually land).
3. PR → human merge.
4. `/finish {branch}` — pulls main forward, removes the worktree.
Then repeat for the next branch.

The point of sync-before-validate: each branch is validated against the state it will
actually merge into, so the Nth landing cannot be green in isolation yet broken once its
siblings are present.

**Promotion note** — this stays documentation until it has been run manually ~3 times.
Only then consider commandifying it, per CLAUDE.md's promote-after-three rule and ADR-0005's
shape test (a long interactive multi-session workflow leans skill, not a one-shot `$ARGUMENTS`
command — so even at promotion time it is not obviously a command).

## When NOT to use

Trivial one-line changes don't need the full loop — use judgment. The ceremony pays off for
anything with real design surface or more than a couple of steps.
