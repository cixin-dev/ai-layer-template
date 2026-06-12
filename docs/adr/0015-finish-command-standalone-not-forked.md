# `/finish` is a standalone command, not a fork of `superpowers:finishing-a-development-branch`

The `/finish` command was written from scratch rather than wrapping or forking the upstream
`superpowers:finishing-a-development-branch` skill. The upstream skill's Option 1 (merge the
feature branch into the base locally) directly violates the never-commit-to-main invariant from
`CLAUDE.md`. Its branch deletion uses `git branch -d`, which fails under this repo's squash-merge
flow because squash-merge creates no merge commit on the feature branch, so git considers the
branch "not fully merged."

## Why not fork

ADR-0004 sets the bar for forking an upstream skill: a fork is warranted only when the skill's
output would pollute this repo's glossary. Here the conflict is behavioral (invariant violation
and wrong flag), not terminological. ADR-0004's bar is not met, so a fork is rejected.

## Why not wrap

A thin wrapper that delegates to the skill still exposes the conflicting paths. The "standalone"
approach is the only one that lets this repo own the behavior completely — squash-merge-aware
`-D`, worktree path resolved from `git worktree list` rather than assumed, and no local-merge
path at all.

## Alternatives rejected

- **Wrap** — a thin wrapper delegates to the skill but still exposes the conflicting local-merge
  and `-d` paths; any upstream update that changes those paths would break this repo's invariant
  silently.
- **Fork** — ADR-0004's bar (glossary pollution) is not met; a fork for behavioral reasons alone
  creates maintenance burden without the terminological justification ADR-0004 requires.
- **`delete_branch_on_merge` alone** — a GitHub repository setting, not portable to other repos
  or the template itself. Belt-and-braces useful, but not a replacement for an explicit cleanup
  command that also handles the worktree and `git pull`.
