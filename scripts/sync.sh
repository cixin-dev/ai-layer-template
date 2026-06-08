#!/usr/bin/env bash
set -euo pipefail

# Symlink each owned skill/command into ~/.claude/{skills,commands}/.
# Owned items are discovered dynamically from this repo's .claude/ tree.
#
# Usage:
#   sync.sh [--dry-run]
#
#   --dry-run   Print what would happen; change nothing.
#   -h|--help   Show this help.

DRY_RUN=0

usage() {
  sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) echo "error: unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# SYNC_REPO_DIR allows tests to point the script at a fixture repo.
REPO_DIR="${SYNC_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# CLAUDE_HOME allows tests to redirect ~/.claude to a temp dir.
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

note() { echo "[sync] $*"; }

if [ "$DRY_RUN" -eq 1 ]; then
  note "DRY RUN — no changes will be made"
fi

# Ensure target dirs exist (real run only).
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands"
fi

# Link a single owned item. Policy:
#   - already correct symlink → skip (idempotent)
#   - real file/dir (not a symlink) → warn and skip (user data)
#   - absent or stale symlink → link/relink (owned names win)
link_item() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    note "warn: $dst is a real file/directory — skipped"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would link: $dst -> $src"
  else
    ln -sfn "$src" "$dst"
    note "linked: $dst -> $src"
  fi
}

# Skills: each subdirectory under .claude/skills/
skills_src="$REPO_DIR/.claude/skills"
if [ -d "$skills_src" ]; then
  for skill_dir in "$skills_src"/*/; do
    [ -d "$skill_dir" ] || continue
    name="$(basename "${skill_dir%/}")"
    link_item "$skills_src/$name" "$CLAUDE_DIR/skills/$name"
  done
fi

# Commands: each .md file under .claude/commands/
commands_src="$REPO_DIR/.claude/commands"
if [ -d "$commands_src" ]; then
  for cmd_file in "$commands_src"/*.md; do
    [ -f "$cmd_file" ] || continue
    name="$(basename "$cmd_file")"
    link_item "$commands_src/$name" "$CLAUDE_DIR/commands/$name"
  done
fi
