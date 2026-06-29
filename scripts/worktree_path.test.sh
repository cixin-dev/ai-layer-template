#!/usr/bin/env bash
# Regression test for the worktree-path resolver (retroactive:
# clean-worktree-wrong-worktree). Drives the resolver against a fixed porcelain
# fixture — no real worktrees needed — so it is deterministic and self-contained.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/worktree_path.sh"

FAILURES=0

# A 3-worktree porcelain listing: main, then two ADJACENT feature worktrees.
# feat/56 is immediately followed by feat/57 — the exact adjacency that made the
# old `grep -A2` resolver return the NEXT worktree's path (feat/57) when asked
# for feat/56, nearly force-deleting an unmerged worktree.
PORCELAIN="$(cat <<'EOF'
worktree /repo
HEAD 0f1dc12
branch refs/heads/main

worktree /repo-feat/56-night-shift-decide
HEAD aaaa111
branch refs/heads/feat/56-night-shift-decide

worktree /repo-feat/57-night-shift-loop-state
HEAD 6981d5f
branch refs/heads/feat/57-night-shift-loop-state
EOF
)"

# check <expected-path> <branch> <description>
check() {
  local expected="$1" branch="$2" desc="$3" output
  output="$(printf '%s\n' "$PORCELAIN" | bash "$RESOLVE" "$branch")"
  if [ "$output" != "$expected" ]; then
    echo "FAIL: $desc (expected '$expected', got '$output')"
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# Bug 1: a branch must resolve to ITS OWN path, never the next entry's.
# ---------------------------------------------------------------------------
check "/repo-feat/56-night-shift-decide" "feat/56-night-shift-decide" \
  "resolves the target worktree, not the one listed after it"
check "/repo-feat/57-night-shift-loop-state" "feat/57-night-shift-loop-state" \
  "resolves the last worktree in the list"
check "/repo" "main" \
  "resolves the first worktree in the list"

# ---------------------------------------------------------------------------
# Anchoring: a prefix of a real branch must match NOTHING (no false target).
# ---------------------------------------------------------------------------
check "" "feat/5" \
  "prefix 'feat/5' does not match feat/56 or feat/57"
check "" "feat/56" \
  "prefix 'feat/56' does not match feat/56-night-shift-decide"
check "" "does-not-exist" \
  "absent branch resolves to empty"

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
