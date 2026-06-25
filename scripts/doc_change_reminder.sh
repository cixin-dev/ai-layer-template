#!/usr/bin/env bash
# Non-blocking reminder run by the local validate gate (validate.sh, ADR-0009).
# If this branch's diff vs the default branch touches canonical docs
# (CONTEXT.md or docs/adr/), the PR body must carry a "## 變更說明" section
# (Traditional Chinese) or the CI `doc-gate` check (ADR-0022) will mark it red.
#
# The PR body does not exist locally, so this can only REMIND, never block — it
# surfaces the requirement at validate time (in front of the agent, before the PR
# is opened) rather than only after CI runs. On a free-plan private repo the CI
# `doc-gate` check cannot be made a required status check, so this reminder + the
# visible red CI mark are the available floor. ALWAYS exits 0.
set -euo pipefail

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

branch=$(git branch --show-current 2>/dev/null || true)

# Detect the default branch (main/master/trunk/develop), mirroring piv_check.sh.
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

# On the default branch (or detached/unknown) there is no PR diff to consider.
[ -z "$branch" ] && exit 0
[ "$branch" = "$default_branch" ] && exit 0

# Resolve the base ref: prefer local, fall back to origin/.
base_ref="$default_branch"
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  base_ref="origin/$default_branch"
  git rev-parse --verify "$base_ref" >/dev/null 2>&1 || exit 0
fi

changed=$(git diff --name-only "${base_ref}..HEAD" 2>/dev/null || true)
if printf '%s\n' "$changed" | grep -qE '^CONTEXT\.md$|^docs/adr/'; then
  cat >&2 << 'MSG'
[doc-change-reminder] This branch touches canonical docs (CONTEXT.md or docs/adr/).
  → The PR body MUST include a "## 變更說明" section (Traditional Chinese), or the
    CI `doc-gate` check will mark the PR red (ADR-0022). This is a reminder, not a
    block — the gate cannot read the PR body locally.
  → 提醒:PR body 要放「## 變更說明」段落(繁體中文),否則 CI 的 doc-gate 會亮紅燈。
MSG
fi

exit 0
