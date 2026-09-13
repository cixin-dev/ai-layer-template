#!/usr/bin/env bash
# harness_freshness.sh — SessionStart hook: is the user-scope harness fresh?
#
# The harness reaches every downstream project through ~/.claude/{commands,skills}
# symlinks into source checkouts (ADR-0007) and real-file hook copies (ADR-0012).
# Both go stale silently: nothing re-runs `git pull` + `sync.sh` except operator
# memory, and a safeguard that depends on memory is not one (ADR-0010). The hook
# copies sat stale for three months (2026-06-13 → 2026-09-13) and two retroactives
# never reached the live hooks. This hook makes staleness visible at every
# session start (ADR-0029).
#
# Source repos are discovered by resolving the symlinks — never hardcoded. Per repo:
#   (a) HEAD behind its upstream            — fetch at most once per FETCH_MINUTES; fail open
#   (b) not on the default branch, or dirty — downstream sessions run unreviewed edits
#   (d) <repo>/.claude/hooks/* missing from, or differing to, ~/.claude/hooks/*
# Over ~/.claude/{commands,skills} themselves:
#   (c) dangling symlinks
# Over the `claude` binary scripts and cron will exec (never the shell's alias):
#   (e) PATH `claude` is not ~/.claude/local/claude while that local install exists
# Over every ~/.claude/{skills/*/SKILL.md,commands/*.md} (linked or real):
#   (f) a `Call the Skill tool with "X"` step whose X is not in ~/.claude/skills, or is
#       `disable-model-invocation: true` (the harness drops it from the model's listing)
#
# Hook mode (default): one line per finding on stdout (lands in context), silent
# when green (no alarm fatigue), ALWAYS exit 0 — never block a session start.
# --strict: exit 1 on any finding (tests, manual runs). Do NOT wire --strict into
# validate.sh: check (b) fires by design in every retroactive/* session, which
# works in the main checkout.
#
# Usage: harness_freshness.sh [--strict]
# Env:   CLAUDE_HOME                      (default ~/.claude)
#        HARNESS_FRESHNESS_FETCH_MINUTES  (default 1440; 0 = always fetch)
#        HARNESS_FRESHNESS_FETCH_TIMEOUT  (seconds; default 5)

# No `set -e`: a hook that aborts on one bad repo hides every other finding.
set -uo pipefail

STRICT=0
case "${1:-}" in
  --strict) STRICT=1 ;;
  -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "error: unknown option: $1" >&2; exit 2 ;;
esac

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
FETCH_MINUTES="${HARNESS_FRESHNESS_FETCH_MINUTES:-1440}"
FETCH_TIMEOUT="${HARNESS_FRESHNESS_FETCH_TIMEOUT:-5}"

# Never let git hold a session start on a credential or host-key prompt.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

FINDINGS=0
finding() {
  echo "[harness-freshness] $*"
  FINDINGS=$((FINDINGS + 1))
}

# --- Discover source repos from the symlinks; flag dangling links on the way (c) ---
repo_list=""
for dir in "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills"; do
  [ -d "$dir" ] || continue
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    if [ ! -e "$link" ]; then
      finding "dangling symlink: $link -> $(readlink "$link")"
      continue
    fi
    target="$(readlink -f "$link")"
    [ -d "$target" ] || target="$(dirname "$target")"
    top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || continue
    repo_list="$repo_list$top
"
  done
done
repos="$(printf '%s' "$repo_list" | sort -u)"

# --- (a) behind upstream ---
fetch_once() {
  local repo="$1" remote="$2" fetch_head
  fetch_head="$(git -C "$repo" rev-parse --git-path FETCH_HEAD 2>/dev/null)" || return 0
  case "$fetch_head" in /*) ;; *) fetch_head="$repo/$fetch_head" ;; esac
  # Throttle: skip when FETCH_HEAD was touched within the window.
  if [ "$FETCH_MINUTES" -gt 0 ] && [ -f "$fetch_head" ] \
     && [ -n "$(find "$fetch_head" -mmin "-$FETCH_MINUTES" 2>/dev/null)" ]; then
    return 0
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$FETCH_TIMEOUT" git -C "$repo" fetch -q "$remote" >/dev/null 2>&1 || true
  else
    git -C "$repo" fetch -q "$remote" >/dev/null 2>&1 || true
  fi
}

check_behind() {
  local repo="$1" up behind
  up="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || return 0
  fetch_once "$repo" "${up%%/*}"
  behind="$(git -C "$repo" rev-list --count "HEAD..$up" 2>/dev/null)" || return 0
  if [ "$behind" -gt 0 ]; then
    finding "$repo: $behind commit(s) behind $up — pull it, then re-run its sync"
  fi
}

# --- (b) not on the default branch, or dirty ---
check_branch_state() {
  local repo="$1" branch default b
  branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
  default="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  default="${default#origin/}"
  if [ -z "$default" ]; then
    for b in main master; do
      if git -C "$repo" rev-parse -q --verify "$b" >/dev/null 2>&1; then default="$b"; break; fi
    done
  fi
  default="${default:-main}"
  if [ "$branch" != "$default" ]; then
    finding "$repo: on '${branch:-detached HEAD}', not '$default' — downstream sessions run unreviewed edits"
  fi
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
    finding "$repo: working tree dirty — downstream sessions run unreviewed edits"
  fi
}

# --- (d) hook copies vs. source ---
check_hook_copies() {
  local repo="$1" src name
  [ -d "$repo/.claude/hooks" ] || return 0
  for src in "$repo/.claude/hooks"/*; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    if [ ! -f "$CLAUDE_DIR/hooks/$name" ]; then
      finding "hook copy missing: $CLAUDE_DIR/hooks/$name (source $src) — run scripts/sync.sh"
    elif ! cmp -s "$src" "$CLAUDE_DIR/hooks/$name"; then
      finding "hook copy stale: $CLAUDE_DIR/hooks/$name differs from $src — run scripts/sync.sh"
    fi
  done
}

# --- (e) PATH `claude` is not the local install ---
# A ~/.bashrc alias hides a stale PATH binary from the operator's shell; scripts and
# cron never see aliases (night_shift_run.sh resolved a root-owned npm-global 1.0.8
# while the session ran ~/.claude/local/claude 2.1.269 — retroactive: claude-path-floor).
_claude_ver() {  # path → first token of `--version`, or "?"
  local v
  if command -v timeout >/dev/null 2>&1; then
    v="$(timeout 5 "$1" --version 2>/dev/null | awk 'NR==1{print $1}')"
  else
    v="$("$1" --version 2>/dev/null | awk 'NR==1{print $1}')"
  fi
  printf '%s' "${v:-?}"
}
check_path_claude() {
  local local_bin="$CLAUDE_DIR/local/claude" path_bin
  [ -x "$local_bin" ] || return 0
  path_bin="$(command -v claude 2>/dev/null)" || return 0
  [ "$(readlink -f "$path_bin")" = "$(readlink -f "$local_bin")" ] && return 0
  finding "PATH claude is $path_bin ($(_claude_ver "$path_bin")), not $local_bin ($(_claude_ver "$local_bin")) — scripts and cron get the PATH one; remove it or put $CLAUDE_DIR/local first on PATH"
}

# --- (f) Skill-tool dependency closure ---
# Hand-picked symlinks (ADR-0007) satisfy only the names the operator picked; a skill's
# own `Call the Skill tool with "X"` step needs X linked too, and model-invoked: the
# harness refuses a `disable-model-invocation: true` skill at the Skill tool ("Ask the
# user to run /X themselves" — probed 2026-09-13), so no skill can reach one. grill-me /
# grill-with-docs / triage sat broken on "grilling" / "domain-modeling" for months
# (retroactive: skill-dep-closure). Plugin-namespaced names (`a:b`) are not user-scope
# files and are skipped.
_user_invoked() {  # SKILL.md → rc 0 when its frontmatter says disable-model-invocation: true
  # awk must exit 0 on the closing fence: under pipefail its rc would become the function's.
  awk 'NR==1 { if ($0 != "---") exit; next } /^---/ { exit } { print }' "$1" 2>/dev/null \
    | grep -qE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$'
}
check_skill_deps() {
  local f dep target
  for f in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    # shellcheck disable=SC2013  # names match [a-z0-9_-]+ — no whitespace to split on
    for dep in $(grep -h 'Skill tool' "$f" 2>/dev/null | grep -oE '"[a-z0-9][a-z0-9_-]*"' | tr -d '"' | sort -u); do
      target="$CLAUDE_DIR/skills/$dep/SKILL.md"
      if [ ! -f "$target" ]; then
        finding "skill dependency missing: $f calls the Skill tool with \"$dep\" but $CLAUDE_DIR/skills/$dep is not linked — link it from its source repo or the step cannot fire"
      elif _user_invoked "$target"; then
        finding "skill dependency unreachable: $f calls the Skill tool with \"$dep\" but it is disable-model-invocation: true — only the human can run it; rephrase the step as 'tell the user to run /$dep'"
      fi
    done
  done
}

repo_count=0
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  repo_count=$((repo_count + 1))
  check_behind "$repo"
  check_branch_state "$repo"
  check_hook_copies "$repo"
done <<EOF
$repos
EOF
check_path_claude
check_skill_deps

if [ "$FINDINGS" -gt 0 ]; then
  echo "[harness-freshness] $FINDINGS finding(s) — reproduce: bash $0 --strict"
  [ "$STRICT" -eq 1 ] && exit 1
elif [ "$STRICT" -eq 1 ]; then
  echo "[harness-freshness] fresh — $repo_count source repo(s) checked"
fi
exit 0
