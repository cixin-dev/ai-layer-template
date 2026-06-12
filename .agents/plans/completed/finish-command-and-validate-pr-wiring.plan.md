# Plan: /finish Command and Validate PR Wiring

## Summary
We're closing the post-validate guidance gap by adding a `/finish` command that tears down a merged branch's worktree, and by upgrading `/validate` Phase 5 from a single-line "open the PR" to explicit push + `gh pr create` steps with a `Closes #N` body and a deterministic `/finish` handoff. Four other files get lightweight one- or two-line updates to point at `/finish` as the post-merge successor. An ADR records why `/finish` is standalone rather than a fork of the upstream `superpowers:finishing-a-development-branch` skill.

## User Story
As an engineer using the PIV Loop, I want the workflow to guide me from a passing validation all the way through PR creation, review, merge, and branch cleanup so that I never have to remember the right sequence of git commands or risk violating the never-commit-to-main invariant.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | MEDIUM |
| Systems affected | `.claude/commands/`, `.claude/skills/piv-loop/`, `docs/adr/` |
| Issue | #12 |

## Patterns to Follow

### Command frontmatter + phase structure
```markdown
---
description: Execute an implementation plan with per-task validation loops
argument-hint: <path/to/plan.md>
---

# Implement

**Plan**: $ARGUMENTS

This is the **Implement** phase of the [PIV Loop](../skills/piv-loop/SKILL.md). Open it in a
**fresh session** — the plan file is your only inheritance from the Plan phase.
```
// SOURCE: .claude/commands/implement.md:1-12

### Table-driven decision branches
```markdown
| State | Action |
|-------|--------|
| Clean, on main, in sync with origin | Create a feature branch (naming below) |
| Dirty, on main (tracked files modified) | STOP — ask the user to stash or commit first |
```
// SOURCE: .claude/commands/implement.md:32-36

### PASS/FAIL reporting block (validate.md Phase 4)
```markdown
- **PASS**: archive the plan with
  `git mv .agents/plans/{slug}.plan.md .agents/plans/completed/{slug}.plan.md`
  then commit on the branch:
  `git commit -m "docs(plan): archive {slug} plan on green gate"`.
```
// SOURCE: .claude/commands/validate.md:54-58

### ADR format (no frontmatter, heading + Why + Alternatives rejected)
```markdown
# Plan archived by Validate on a green gate, not by Implement

The PIV plan file stays in `.agents/plans/` through Implement and is archived to
`.agents/plans/completed/` by `/validate` when the gate passes...

## Why
...

## Relationship to ADR-0013
...
```
// SOURCE: docs/adr/0013-plan-archived-by-validate-on-green-not-implement.md:1-10

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/commands/finish.md` | CREATE | The `/finish` command |
| `docs/adr/0015-finish-command-standalone-not-forked.md` | CREATE | ADR: why standalone, not a fork |
| `.claude/commands/validate.md` | UPDATE | Phase 5 — explicit push + PR creation + /finish handoff |
| `.claude/commands/implement.md` | UPDATE | Phase 5 — replace bare `git worktree remove` with `/finish` pointer |
| `.claude/skills/piv-loop/SKILL.md` | UPDATE | Validate section — add `→ /finish {branch}` after merge |

## Tasks

### Task 1: Create `.claude/commands/finish.md`
- File: `.claude/commands/finish.md`
- Action: CREATE
- Implement:
  Write the full `/finish` command with the following structure:

  **Frontmatter**: `description: Tear down a merged feature branch — pull main, remove worktree, delete local and remote branch` / `argument-hint: <branch | PR# | blank to infer>`

  **Phase 1 — Resolve the branch**:
  - If argument is a PR number (`#N` or bare integer): `gh pr view {N} --json headRefName --jq .headRefName` to get the branch name.
  - If argument is a branch name: use it directly.
  - If blank: run `git branch --show-current` from current directory (works from inside the feature worktree).

  **Phase 2 — Hard gate: PR must be MERGED**:
  - Run `gh pr list --head {branch} --json state,number,url --limit 1` to find the PR.
  - If no PR found: stop with "No PR found for branch {branch}. Nothing to clean up."
  - If state is OPEN: stop with "PR #{N} is still OPEN. Get it reviewed and merged first."
  - If state is CLOSED (not merged): stop with "PR #{N} was closed without merging. If you want to discard the branch and worktree anyway, re-run as `/finish {branch} --discard`." When `--discard` is present, skip the CLOSED check and proceed.
  - If state is MERGED: proceed.

  **Phase 3 — Cleanup sequence** (run from main repo root; if currently in the worktree, note the user may need to `cd` first, or run cleanup commands from the main repo):
  1. `git pull` — bring main up to date with the squash-merged commit.
  2. Find worktree path: `git worktree list --porcelain | grep -A2 "branch refs/heads/{branch}" | grep "worktree" | awk '{print $2}'`. If no worktree found, skip removal silently.
  3. `git worktree remove {path}` — removes the directory and the worktree registration.
  4. `git branch -D {branch}` — `-D` (force-delete) is required because squash-merge does not create a merge commit; `-d` would fail with "not fully merged".
  5. `git worktree prune` — clean up any stale worktree references.
  6. `git push origin --delete {branch}` — tolerant: if the remote branch is already gone (e.g., `delete_branch_on_merge` removed it), print a note and continue rather than failing.
  7. `git fetch --prune` — sync remote-tracking refs.

  **Phase 4 — Confirm**:
  - Print a brief summary: "Done. main is up to date. Worktree removed. Branch {branch} deleted locally and remotely."
  - Never touch Issue state (PR body's `Closes #N` handles it at merge).

- Mirror: `.claude/commands/validate.md:1-15` (frontmatter + phase structure)
- Validate: `bash .claude/validate.sh` (gate should still pass; finish.md is a new prose file)

### Task 2: Create `docs/adr/0015-finish-command-standalone-not-forked.md`
- File: `docs/adr/0015-finish-command-standalone-not-forked.md`
- Action: CREATE
- Implement:
  Follow the ADR format from 0013/0014 (no frontmatter, plain markdown headings):

  **Title**: `/finish` is a standalone command, not a fork of `superpowers:finishing-a-development-branch`

  **Body**: The `/finish` command was written from scratch rather than wrapping or forking the upstream `superpowers:finishing-a-development-branch` skill. The upstream skill's Option 1 (merge the feature branch into the base locally) directly violates the never-commit-to-main invariant from `CLAUDE.md`. Its branch deletion uses `git branch -d`, which fails under this repo's squash-merge flow because squash-merge creates no merge commit on the feature branch, so git considers the branch "not fully merged."

  **Why not fork**: ADR-0004 sets the bar for forking an upstream skill: the fork is warranted only when the skill's output would pollute this repo's glossary. Here the conflict is behavioral (invariant violation + wrong flag), not terminological. ADR-0004's bar is not met, so a fork is rejected.

  **Why not wrap**: A thin wrapper that delegates to the skill still exposes the conflicting paths. The "standalone" approach is the only one that lets us own the behavior completely — squash-merge-aware `-D`, worktree path resolved from `git worktree list` rather than assumed, and no local-merge path at all.

  **Alternatives rejected** section: (1) wrap — exposes conflicting paths; (2) fork — ADR-0004 bar not met; (3) delete\_branch\_on\_merge alone — a repo setting, not portable to other repos or the template; belt-and-braces but not a replacement for the command.

- Mirror: `docs/adr/0014-plan-seeded-as-first-commit-on-branch.md:1-30` (heading + Why + Alternatives rejected)
- Validate: `bash .claude/validate.sh`

### Task 3: Update `validate.md` Phase 5
- File: `.claude/commands/validate.md`
- Action: UPDATE
- Implement:
  Replace the current Phase 5 section heading and opening line:

  Current:
  ```
  ## Phase 5 — Human review + System Evolution handoff

  On PASS, hand to a human reviewer in a fresh session (open the PR, share the branch).
  ```

  Replace with:
  ```
  ## Phase 5 — Push, open PR, and hand to human review

  On PASS:

  1. **Push the branch** (from inside the feature worktree):
     `git push -u origin {branch}`
  2. **Open the PR**:
     ```
     gh pr create \
       --title "{short title from plan summary}" \
       --body "$(cat <<'EOF'
     ## Summary
     {plan summary paragraph}

     ## Report
     `.agents/reports/{plan-name}-report.md`

     Closes #{N}
     EOF
     )"
     ```
     Include `Closes #{N}` only when the plan carries an Issue number. Pull the summary from the plan's `## Summary` section and the report path from `.agents/reports/{plan-name}-report.md`.
  3. **Share the PR URL** with reviewers.

  **Review-fix loop** — if reviewers request changes: open a fresh session inside the feature worktree, address the comments, re-run `/validate` (which falls back to `completed/` for re-validation — the archive step is idempotent), then push the update with `git push`.

  **Successor**: after the PR merges, run `/finish {branch}` in a fresh session from the main repo to pull main up to date, remove the worktree, and delete the local and remote branch.
  ```

  Keep the remaining System Evolution handoff paragraph unchanged.

- Mirror: `.claude/commands/validate.md:54-70` (PASS block style) and `implement.md:1-12` (phase heading style)
- Validate: `bash .claude/validate.sh`

### Task 4: Update `implement.md` Phase 5
- File: `.claude/commands/implement.md`
- Action: UPDATE
- Implement:
  Find the last paragraph of Phase 5 (the worktree cleanup line):

  Current (last two sentences of Phase 5):
  ```
  The next step is **`/validate <plan-path>`** in a fresh session (full gate + E2E + human
  review entry), then open a PR.

  Include the worktree cleanup command for after the PR merges:
  `git worktree remove ../{worktree-path}`
  ```

  Replace with:
  ```
  The next step is **`/validate <plan-path>`** in a fresh session (full gate + E2E + human
  review entry), then open a PR.

  After the PR merges, run **`/finish {branch}`** from the main repo to pull main up to date,
  remove the worktree, and delete the local and remote branch.
  ```

- Mirror: `.claude/commands/implement.md` — match surrounding prose style
- Validate: `bash .claude/validate.sh`

### Task 5: Update `piv-loop/SKILL.md` Validate section
- File: `.claude/skills/piv-loop/SKILL.md`
- Action: UPDATE
- Implement:
  Find the Validate paragraph in the "The three phases" section:

  Current:
  ```
  **Validate** — **Fresh session.** Run the full gate (`validate.sh` + the plan's E2E
  checklist), then hand to human review. Pass → merge. Problem → deterministic handoff to
  [`/retroactive`](../system-evolution/SKILL.md) in a fresh session (the System Evolution
  trigger — workflow-routed, not a hook).
  → run `/validate <plan-path>`.
  ```

  Replace with:
  ```
  **Validate** — **Fresh session.** Run the full gate (`validate.sh` + the plan's E2E
  checklist), then hand to human review. Pass → push + open PR → merge → run
  `/finish {branch}`. Problem → deterministic handoff to
  [`/retroactive`](../system-evolution/SKILL.md) in a fresh session (the System Evolution
  trigger — workflow-routed, not a hook).
  → run `/validate <plan-path>`.
  ```

- Mirror: `.claude/skills/piv-loop/SKILL.md:28-33` (existing Validate block)
- Validate: `bash .claude/validate.sh`

## Validation
```bash
bash .claude/validate.sh
# Runs:
#   bash scripts/sync.test.sh
#   bash scripts/unsync.test.sh
#   bash scripts/validate_gate.test.sh
```
All changes are to markdown command/skill/ADR files — the shell test suite passes independent of them. The gate should be green with no changes needed.

**E2E checks** (manual, post-implement):
- [ ] `/finish --help` (or `/finish` with no arg on a branch that has a merged PR) runs the full resolution and cleanup sequence without errors.
- [ ] `/finish` on a branch whose PR is OPEN prints the OPEN-gate error and exits.
- [ ] `/finish` on a branch whose PR is CLOSED-unmerged prints the CLOSED-gate message and exits (without `--discard`).
- [ ] `/validate` PASS output includes `git push -u origin` step and `gh pr create` invocation with `Closes #N`.
- [ ] `implement.md` no longer contains `git worktree remove`.
- [ ] ADR-0015 exists at `docs/adr/0015-finish-command-standalone-not-forked.md`.

## Acceptance Criteria
- [ ] `/finish` refuses to act on an OPEN or CLOSED-unmerged PR (hard MERGED gate)
- [ ] `/finish` on a merged PR leaves: main up to date, worktree removed, local branch deleted, remote branch absent, `git worktree list` clean
- [ ] `/validate` PASS output ends with a created PR (body carries `Closes #N`) and names `/finish` as the post-merge step
- [ ] `implement.md` no longer instructs manual `git worktree remove`
- [ ] ADR-0015 committed alongside all other changes
- [ ] All tasks completed
- [ ] `bash .claude/validate.sh` passes with zero errors
- [ ] Follows existing command/ADR patterns
