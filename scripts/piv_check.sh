#!/usr/bin/env bash
# Verify PIV artifact invariants for the current session's working tree.
set -euo pipefail

FAILURES=0

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[piv-check] not a git repo; skipping" >&2
  exit 0
fi

branch=$(git branch --show-current 2>/dev/null || true)

# Detect the default branch (main/master/trunk/develop).
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || true)
if [ -z "$default_branch" ]; then
  for b in main master trunk develop; do
    if git rev-parse --verify --quiet "$b" >/dev/null 2>&1; then
      default_branch="$b"
      break
    fi
  done
fi
default_branch="${default_branch:-main}"

# PIV checks only apply to feature branches.
if [ -z "$branch" ] || [ "$branch" = "$default_branch" ]; then
  echo "PIV checks skipped (not on a feature branch)."
  exit 0
fi

# Non-PIV branches have no plan phase and are identified by prefix:
#   retroactive/*       — System Evolution (outer loop)
#   prd/* , align/*     — Phase 1 Strategic Planning / Alignment (PRDs, glossary
#                         CONTEXT.md, ADRs, grill-with-docs output)
#   chore/* , docs/*    — maintenance (archiving completed designs, dep bumps,
#                         doc edits) — no plan/implement/validate cycle to gate
# Prefix-based (not diff-based) so a Phase-1 branch that also touches harness
# machinery — e.g. the commit that adds this very exemption — is still exempt.
case "$branch" in
  retroactive/*|prd/*|align/*|chore/*|docs/*)
    echo "PIV checks skipped (non-PIV branch: $branch)."
    exit 0
    ;;
esac

# Resolve the base ref against which the branch's OWN commits are measured.
# The integration line lives in two refs that can drift: local <default> and
# origin/<default>. A clone whose local <default> lags origin/ — a sibling PR
# squash-merged into origin/ mid-drive but never fast-forwarded into local
# (Night Shift #97) — would, if measured against the stale local ref, mis-read
# that already-integrated upstream commit as the branch's FIRST commit and trip
# Check 1. Subtract the MORE-ADVANCED of the two (the one that has the other as
# an ancestor) so every already-integrated commit is excluded regardless of
# which ref lags. Offline clones with only a local ref use it; if neither
# exists, skip.
local_ref=""; origin_ref=""
if git rev-parse --verify "$default_branch" >/dev/null 2>&1; then local_ref="$default_branch"; fi
if git rev-parse --verify "origin/$default_branch" >/dev/null 2>&1; then origin_ref="origin/$default_branch"; fi
if [ -n "$local_ref" ] && [ -n "$origin_ref" ]; then
  if git merge-base --is-ancestor "$local_ref" "$origin_ref" 2>/dev/null; then
    base_ref="$origin_ref"   # local lags (or equals) origin → origin is the true tip
  else
    base_ref="$local_ref"    # origin lags or diverged → trust the local integration ref
  fi
elif [ -n "$origin_ref" ]; then
  base_ref="$origin_ref"
elif [ -n "$local_ref" ]; then
  base_ref="$local_ref"
else
  echo "[piv-check] base ref '$default_branch' not found locally or in origin; skipping range checks" >&2
  exit 0
fi

# --- Check 1: plan file is the first commit on the branch ---
first_commit=$(git rev-list --reverse "${base_ref}..HEAD" 2>/dev/null | head -1 || true)
if [ -n "$first_commit" ]; then
  # Capture to a variable first to avoid SIGPIPE/pipefail race with grep -q.
  added_files=$(git diff-tree --no-commit-id -r --diff-filter=A --name-only "$first_commit" 2>/dev/null || true)
  if ! printf '%s\n' "$added_files" | grep -qE "^\.agents/plans/[^/]+\.plan\.md$"; then
    fail "first commit on branch does not add a plan file (.agents/plans/*.plan.md)"
  fi
fi

# --- Check 2: past plan phase → report must exist for every active plan ---
# "Past plan phase" = non-.agents/ files have been changed on this branch.
# Plan-only commits (including plan amendments) are not counted.
branch_files=$(git diff --name-only "${base_ref}..HEAD" 2>/dev/null || true)
non_plan_diff=$(printf '%s\n' "$branch_files" | grep -v "^\.agents/" || true)
if [ -n "$non_plan_diff" ]; then
  while IFS= read -r plan_file; do
    [ -z "$plan_file" ] && continue
    plan_name=$(basename "$plan_file" .plan.md)
    expected_report=".agents/reports/${plan_name}-report.md"
    if [ ! -f "$expected_report" ]; then
      fail "active plan '${plan_name}' has no matching report at ${expected_report} — implement session may be incomplete"
    fi
  done < <(find .agents/plans -maxdepth 1 -name "*.plan.md" 2>/dev/null || true)
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "PIV checks passed."
else
  echo "$FAILURES PIV check(s) failed."
fi
exit "$FAILURES"
