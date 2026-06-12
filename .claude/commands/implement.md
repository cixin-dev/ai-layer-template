---
description: Execute an implementation plan with per-task validation loops
argument-hint: <path/to/plan.md>
---

# Implement

**Plan**: $ARGUMENTS

This is the **Implement** phase of the [PIV Loop](../skills/piv-loop/SKILL.md). Open it in a
**fresh session** — the plan file is your only inheritance from the Plan phase.

**Golden rule**: if validation fails, fix it before moving on. Never accumulate broken
state.

---

## Phase 1 — Load

Read the plan and extract: summary, patterns to mirror, files to change, the ordered task
list, the validation commands, and any Issue number. If the plan is missing, stop and tell the
user to run `/plan` first.

## Phase 2 — Prepare

Check git state.

| State | Action |
|-------|--------|
| Clean, on main, in sync with origin | Create a feature branch (naming below) |
| Clean, on main but ahead of origin/main | STOP — main has local-only commits, which breaks the never-commit-to-main rule. Surface them to the user and resolve (move to a branch, or push if truly intended) before proceeding — do not silently auto-push |
| Dirty, on main | STOP — ask the user to stash or commit first |
| On a feature branch | Use it |

Before branching, run `git log origin/main..main --oneline` as a tripwire — main should never
be ahead of origin (every change flows through a branch + PR; see CLAUDE.md Do-not). If commits
appear, the invariant was breached upstream: stop and surface them rather than silently pushing,
since a local-only main commit becomes a divergence after the next squash-merge.

Branch name: `feat/{N}-{slug}` when the plan carries an Issue number (the Issue's number plus
a short slug); otherwise `feat/{plan-name}` (the plan file's kebab-case name).

### Worktree isolation

After determining the branch name, check `git worktree list` for an existing worktree on
that branch. Then:

| Worktree state | Action |
|----------------|--------|
| Worktree already exists for branch | Use that directory for all work |
| Branch doesn't exist yet | `git worktree add -b {branch} ../{repo-dirname}-{branch} main` (atomic; main stays on main) |
| Branch exists but no worktree | `git worktree add ../{repo-dirname}-{branch} {branch}` |

Never run `git checkout -b` before `git worktree add` — that switches the main worktree to the feature branch, causing the subsequent `worktree add` to fail with "already used by worktree."

All implementation work (Phases 3–5) happens inside the worktree directory, not the main
repo. This keeps parallel feature sessions from interfering with each other via
branch-switching.

Worktree path convention: `../{repo-dirname}-{branch}` — e.g.
`../ai-layer-template-feat01-sync-sh-retire-install`.

## Phase 3 — Execute

For each task, in order:

1. **Verify assumptions.** Read the target file and its neighbors (what it imports, what
   imports it). Confirm the functions/types/endpoints the plan references actually exist
   and match. If the plan is wrong, adapt — and document the deviation.
2. **Implement.** Follow the mirror reference. Check integration: do imports resolve, do
   callers still work, does data flow correctly across boundaries?
3. **Write tests for new behavior.** Every new behavior gets at least one test covering the
   public interface, error cases, and cross-boundary behavior. Tests come before marking the
   task done — not after.
4. **Validate immediately.** Run the project's check command (which must include the tests
   you just wrote). On failure: read the error, fix the root cause, re-run, proceed only
   when green.
5. **Track progress** with a simple per-task ✅, and record any deviation from the plan
   and why.

Prefer vertical tracer-bullet slices over a horizontal "all tasks at once" pass — see
[`tdd-gate.md`](../skills/tdd-gate/SKILL.md).

## Phase 4 — Report

Write `.agents/reports/{plan-name}-report.md` capturing: tasks completed, validation
results, files changed, deviations from plan (with rationale), and tests written. Leave the
plan in `.agents/plans/` — `/validate` archives it to `completed/` on a green gate. A plan is
"completed" only once it passes validation, not when implementation ends, so archiving is
Validate's job, not yours.

**Norm — self-check before Phase 5 output.** This is a soft gate you honor, not a
hook-enforced floor (the validate gate is the only hook-enforced floor; file existence here
has no clean hook seam — see ADR-0009 for the distinction). Do not output Phase 5 until:
- [ ] `.agents/reports/{plan-name}-report.md` exists

If an Issue number was in the plan metadata, add a comment to the Issue (`gh issue comment {N}`)
summarizing what shipped, the branch, file/test counts, and deviations. Do **not** change the
Issue's state — closing it or moving its labels belongs to Validate / human review, not the
implementer (self-promoting your own work defeats the PIV separation). Comment only; leave the
Issue open.

## Phase 5 — Output

Report branch, per-task validation results, files changed, deviations, and artifact paths.
The next step is **`/validate <plan-path>`** in a fresh session (full gate + E2E + human
review entry), then open a PR.

Include the worktree cleanup command for after the PR merges:
`git worktree remove ../{worktree-path}`
