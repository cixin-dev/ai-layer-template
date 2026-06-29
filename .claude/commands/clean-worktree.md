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

Run `gh pr list --head {branch} --json state,number,url,headRefOid --limit 1 --state all`
to find the PR. Keep `headRefOid` — it is the exact commit that was merged, and Phase 3's
rescue check needs it.

| State | Action |
|-------|--------|
| No PR found | STOP — "No PR found for branch {branch}. Nothing to clean up." |
| OPEN | STOP — "PR #{N} is still OPEN. Get it reviewed and merged first." |
| CLOSED (not merged) | STOP — "PR #{N} was closed without merging. If you want to discard the branch and worktree anyway, re-run as `/clean-worktree {branch} --discard`." Skip this check when `--discard` is present in `$ARGUMENTS`. |
| MERGED | Proceed (remember `{headRefOid}`) |

## Phase 3 — Cleanup sequence

Run these commands from the **main repo root**. If currently inside the feature worktree,
note that the user may need to `cd` to the main repo first, or the commands can be run with
the main repo as the working directory.

1. `git checkout {default_branch}` — ensure HEAD is on the default branch before pulling.
   (Running from inside the feature branch is the common case; without this the pull targets
   the already-deleted remote tracking ref and exits 1.)
2. `git pull` — bring main up to date with the squash-merged commit.
3. Find the worktree path:
   ```
   git worktree list --porcelain | bash scripts/worktree_path.sh {branch}
   ```
   This resolves the worktree by **exact** branch match. Do **not** hand-roll a
   `grep -A2 "branch refs/heads/{branch}"` here: in porcelain the `branch` line is the
   *last* line of an entry, so scanning forward returns the *next* worktree's path —
   the footgun this script exists to prevent (see `scripts/worktree_path.sh` header,
   tested by `scripts/worktree_path.test.sh`). If no worktree path is found, skip steps
   4–4b silently.
4. **Rescue check** — before touching the worktree, check for commits added to it
   **after the PR was merged** (the only unmerged risk left, since Phase 2 already
   confirmed the PR is MERGED):
   ```
   git -C {path} log {headRefOid}..HEAD --oneline
   ```
   `{headRefOid}` is the exact tip that was merged (from Phase 2). Do **not** use
   `main..HEAD`: squash-merge does not make the feature branch's commits ancestors of
   main, so `main..HEAD` is *always* non-empty for a squash-merged branch (and stays
   non-empty when main is merely advanced by other PRs) — a guaranteed false positive.
   - If the output is **empty** (or git reports `{headRefOid}` as an unknown revision —
     the local branch is *behind* the merged tip and holds no local-only work): proceed
     directly to step 4a.
   - If the output is **non-empty** (commits were added to the worktree after the merge):
     **STOP and report**:
     ```
     ⚠️  {branch} has {N} commit(s) added after the PR was merged:
       {log lines}
     These were not part of the merged PR. Options:
       a) Cherry-pick them to a new branch and open a follow-up PR — safest.
       b) Discard them (re-run with --discard) — they are gone permanently.
     Do NOT push to main without explicit user instruction.
     ```
     Wait for the user to decide. Do not autonomously cherry-pick or push to main.
4a. `git worktree remove {path}` — removes the directory and the worktree registration.
    If this fails with "contains modified or untracked files":
    - Run `git -C {path} status --short` and show the user what would be lost.
    - STOP and report: "Worktree has untracked/modified files (listed above). Re-run with
      `--discard` to force-remove them, or save them first."
    - Only use `--force` if `--discard` is present in `$ARGUMENTS`.
4b. `git branch -D {branch}` — `-D` (force-delete) is required because squash-merge does not
   create a merge commit on the feature branch; `-d` would fail with "not fully merged".
5. `git worktree prune` — clean up any stale worktree references.
6. `git push origin --delete {branch} 2>/dev/null || echo "remote branch already gone — continuing"`
   — the `|| echo` absorbs the expected "remote ref does not exist" when GitHub already
   deleted the branch on merge (`delete_branch_on_merge`, the common case here), so the step
   returns `0` instead of erroring or breaking a `&&`-chained run. Keep the resilience **in the
   command**, not as a prose caveat on a bare `git push --delete` — a bare delete surfaces the
   error and, when chained, aborts step 7.
7. `git fetch --prune` — sync remote-tracking refs.

## Phase 4 — Confirm

Print a brief summary:

```
Done. main is up to date. Worktree removed. Branch {branch} deleted locally and remotely.
```

Never touch Issue state — the PR body's `Closes #N` handles it at merge.
