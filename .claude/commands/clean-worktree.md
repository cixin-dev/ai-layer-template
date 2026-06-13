---
description: Tear down a merged feature branch — pull main, remove worktree, delete local and remote branch
argument-hint: <branch | PR# | blank to infer> [--discard]
---

# Clean Worktree

Tear down a feature branch after its PR has been merged. Runs from the **main repo root**
(not from inside the feature worktree).

---

## Phase 1 — Resolve the branch

Determine the branch name from `$ARGUMENTS`:

| Input | Action |
|-------|--------|
| PR number (`#N` or bare integer) | `gh pr view {N} --json headRefName --jq .headRefName` |
| Branch name | Use it directly |
| Blank | `git branch --show-current` (works from inside the feature worktree too) |

## Phase 2 — Hard gate: PR must be MERGED

Run `gh pr list --head {branch} --json state,number,url --limit 1 --state all` to find the PR.

| State | Action |
|-------|--------|
| No PR found | STOP — "No PR found for branch {branch}. Nothing to clean up." |
| OPEN | STOP — "PR #{N} is still OPEN. Get it reviewed and merged first." |
| CLOSED (not merged) | STOP — "PR #{N} was closed without merging. If you want to discard the branch and worktree anyway, re-run as `/clean-worktree {branch} --discard`." Skip this check when `--discard` is present in `$ARGUMENTS`. |
| MERGED | Proceed |

## Phase 3 — Cleanup sequence

Run these commands from the **main repo root**. If currently inside the feature worktree,
note that the user may need to `cd` to the main repo first, or the commands can be run with
the main repo as the working directory.

1. `git pull` — bring main up to date with the squash-merged commit.
2. Find the worktree path:
   ```
   git worktree list --porcelain | grep -A2 "branch refs/heads/{branch}" | grep "worktree" | awk '{print $2}'
   ```
   If no worktree path is found, skip step 3 silently.
3. `git worktree remove {path}` — removes the directory and the worktree registration.
4. `git branch -D {branch}` — `-D` (force-delete) is required because squash-merge does not
   create a merge commit on the feature branch; `-d` would fail with "not fully merged".
5. `git worktree prune` — clean up any stale worktree references.
6. `git push origin --delete {branch}` — if the remote branch is already gone (e.g.,
   `delete_branch_on_merge` removed it), print a note and continue rather than failing.
7. `git fetch --prune` — sync remote-tracking refs.

## Phase 4 — Confirm

Print a brief summary:

```
Done. main is up to date. Worktree removed. Branch {branch} deleted locally and remotely.
```

Never touch Issue state — the PR body's `Closes #N` handles it at merge.
