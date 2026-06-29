#!/usr/bin/env bash
# Resolve the worktree path checked out at an EXACT branch.
#
# Reads `git worktree list --porcelain` on stdin; prints the matching worktree
# path (empty, exit 0, if no worktree has that branch checked out). Usage:
#   git worktree list --porcelain | scripts/worktree_path.sh <branch>
#
# Why a script and not an inline grep: porcelain emits each entry as
#   worktree <path>
#   HEAD <sha>
#   branch refs/heads/<name>
#   <blank>
# The `branch` line is the LAST line of an entry, so the naive
# `grep -A2 "branch refs/heads/<name>" | grep worktree` reads FORWARD past the
# blank line into the NEXT entry and returns the wrong worktree's path.
# Resolving feat/56 once returned feat/57's path — a near-miss force-deletion of
# an unmerged worktree (retroactive: clean-worktree-wrong-worktree). This awk
# pairs each `branch` line with the `worktree` line that PRECEDES it, and
# matches the ref EXACTLY so `feat/5` cannot prefix-match `feat/56`.
set -euo pipefail

branch="${1:?usage: git worktree list --porcelain | worktree_path.sh <branch>}"

# substr($0, 10) drops the leading "worktree " (9 chars) and keeps the rest of
# the line verbatim, so paths containing spaces survive intact.
awk -v ref="refs/heads/$branch" '
  /^worktree /        { path = substr($0, 10) }
  $0 == "branch " ref { print path; exit }
'
