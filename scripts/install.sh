#!/usr/bin/env bash
set -euo pipefail

# Install the AI Layer (CLAUDE.md, .claude/, examples/) from this template into a target
# project. Copies ONLY the AI Layer — never this script or the README. Existing files are
# preserved unless --force is given.
#
# Usage:
#   install.sh [--dry-run] [--force] <target-dir>
#
#   --dry-run   Print what would happen; change nothing. Always exits 0 on a valid target.
#   --force     Overwrite files that already exist in the target.
#   -h|--help   Show this help.

DRY_RUN=0
FORCE=0
TARGET=""

usage() {
  sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "error: multiple target directories given ('$TARGET' and '$1')" >&2
        exit 2
      fi
      TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "error: no target directory given" >&2
  usage >&2
  exit 2
fi

# Resolve the template root (parent of this script's directory).
SRC="$(cd "$(dirname "$0")/.." && pwd)"

# Only these items are part of the AI Layer. Anything else in the template stays put.
ITEMS=("CLAUDE.md" ".claude" "examples")

note() { echo "[install] $*"; }

if [ "$DRY_RUN" -eq 1 ]; then
  note "DRY RUN — no changes will be made"
fi
note "source: $SRC"
note "target: $TARGET"

# Create the target directory (real run only).
if [ ! -d "$TARGET" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would create target directory: $TARGET"
  else
    mkdir -p "$TARGET"
    note "created target directory: $TARGET"
  fi
fi

copied=0
skipped=0

# Copy a single file, respecting --force and --dry-run.
copy_file() {
  local rel="$1" src="$2" dst="$3"
  if [ -e "$dst" ] && [ "$FORCE" -eq 0 ]; then
    note "skip (exists): $rel  — use --force to overwrite"
    skipped=$((skipped + 1))
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would copy: $rel"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    note "copied: $rel"
  fi
  copied=$((copied + 1))
}

for item in "${ITEMS[@]}"; do
  src_path="$SRC/$item"
  if [ ! -e "$src_path" ]; then
    note "skip (not in template): $item"
    continue
  fi
  if [ -f "$src_path" ]; then
    copy_file "$item" "$src_path" "$TARGET/$item"
  else
    # Directory: walk every file, preserving relative paths, so per-file
    # overwrite protection applies to each leaf.
    while IFS= read -r -d '' f; do
      rel="${f#"$SRC"/}"
      copy_file "$rel" "$f" "$TARGET/$rel"
    done < <(find "$src_path" -type f -print0)
  fi
done

note "done: $copied to copy, $skipped skipped"
exit 0
