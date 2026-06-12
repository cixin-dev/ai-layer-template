#!/usr/bin/env bash
set -euo pipefail

# Reverse of sync.sh: remove owned symlinks from ~/.claude/{skills,commands}/,
# remove copied hook files from ~/.claude/hooks/, and restore or surgically
# clean ~/.claude/settings.json. Only removes items this repo installed — never
# user-created files, real directories, or upstream symlinks.
#
# Usage:
#   unsync.sh [--dry-run]
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

note() { echo "[unsync] $*"; }

if [ "$DRY_RUN" -eq 1 ]; then
  note "DRY RUN — no changes will be made"
fi

ERRORS=0

# Remove a symlink only if it was created by this repo (ownership = readlink matches src).
# Absent or symlink-pointing-elsewhere → silent no-op. Real file/dir → skip with note.
unlink_owned() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note "would remove symlink: $dst"
    else
      rm -f "$dst"
      note "removed symlink: $dst"
    fi
    return
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    note "skip: $dst is a real file/directory — not ours"
    return
  fi
  # absent, or symlink pointing elsewhere (upstream/user) → leave untouched
}

# Remove a hook file installed by this repo. Ownership is by name (not backlink).
# absent → no-op; directory → error (unexpected state); symlink or real file → remove
# (warn first if content differs from repo source).
remove_hook() {
  local src="$1" dst="$2"
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    return
  fi
  if [ -d "$dst" ] && [ ! -L "$dst" ]; then
    note "error: $dst is a directory — unexpected state"
    ERRORS=$((ERRORS + 1))
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would remove hook: $dst"
    return
  fi
  if [ -f "$dst" ] && [ ! -L "$dst" ] && ! cmp -s "$src" "$dst" 2>/dev/null; then
    note "warn: $dst had local modifications — removing anyway"
  fi
  rm -f "$dst"
  note "removed hook: $dst"
}

# Skills: each subdirectory under .claude/skills/
skills_src="$REPO_DIR/.claude/skills"
if [ -d "$skills_src" ]; then
  for skill_dir in "$skills_src"/*/; do
    [ -d "$skill_dir" ] || continue
    name="$(basename "${skill_dir%/}")"
    unlink_owned "$skills_src/$name" "$CLAUDE_DIR/skills/$name"
  done
fi

# Commands: each .md file under .claude/commands/
commands_src="$REPO_DIR/.claude/commands"
if [ -d "$commands_src" ]; then
  for cmd_file in "$commands_src"/*.md; do
    [ -f "$cmd_file" ] || continue
    name="$(basename "$cmd_file")"
    unlink_owned "$commands_src/$name" "$CLAUDE_DIR/commands/$name"
  done
fi

# Hooks: each file under .claude/hooks/
hooks_src="$REPO_DIR/.claude/hooks"
if [ -d "$hooks_src" ]; then
  for hook_file in "$hooks_src"/*; do
    [ -f "$hook_file" ] || continue
    name="$(basename "$hook_file")"
    remove_hook "$hooks_src/$name" "$CLAUDE_DIR/hooks/$name"
  done
fi

# Restore or surgically clean settings.json hook entries.
SETTINGS="$CLAUDE_DIR/settings.json"
SG_CMD="python3 \"$CLAUDE_DIR/hooks/security_guard.py\""
VG_CMD="python3 \"$CLAUDE_DIR/hooks/validate_gate.py\""

if [ -f "$SETTINGS.bak" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would restore: $SETTINGS from $SETTINGS.bak"
  else
    mv "$SETTINGS.bak" "$SETTINGS"
    note "restored: $SETTINGS from backup"
  fi
elif ! command -v python3 >/dev/null 2>&1; then
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would unwire hook: PreToolUse -> security_guard.py"
    note "would unwire hook: Stop -> validate_gate.py"
  else
    note "warn: python3 not found — remove hooks manually from $SETTINGS:"
    note "  remove PreToolUse entry: $SG_CMD"
    note "  remove Stop entry: $VG_CMD"
  fi
else
  python3 - "$SETTINGS" "$SG_CMD" "$VG_CMD" "$DRY_RUN" <<'PYEOF'
import json, sys, pathlib

settings_path = pathlib.Path(sys.argv[1])
sg_cmd = sys.argv[2]
vg_cmd = sys.argv[3]
dry_run = sys.argv[4] == "1"

if not settings_path.exists():
    sys.exit(0)

try:
    data = json.loads(settings_path.read_text())
except Exception as e:
    if dry_run:
        print(f"[unsync] warn: could not read {settings_path} — skipping settings cleanup", flush=True)
    else:
        print(f"[unsync] warn: could not parse {settings_path}: {e} — remove hooks manually", flush=True)
        print(f"[unsync]   remove PreToolUse entry: {sg_cmd}", flush=True)
        print(f"[unsync]   remove Stop entry: {vg_cmd}", flush=True)
    sys.exit(0)

hooks = data.get("hooks", {})
changed = False

def remove_cmd_from_block(block, cmd):
    """Remove a command entry from a hooks block. Returns True if block should be dropped."""
    if not isinstance(block, dict):
        return False
    # Flat-format block with top-level command field
    if block.get("command") == cmd:
        return True
    # Nested hooks list
    hook_list = block.get("hooks")
    if isinstance(hook_list, list):
        new_list = [h for h in hook_list if not (isinstance(h, dict) and h.get("command") == cmd)]
        if len(new_list) < len(hook_list):
            block["hooks"] = new_list
            return len(new_list) == 0
    return False

# Remove security_guard.py from PreToolUse
if "PreToolUse" in hooks:
    pre_list = hooks["PreToolUse"]
    new_pre = []
    for block in pre_list:
        drop = remove_cmd_from_block(block, sg_cmd)
        if drop:
            changed = True
            if dry_run:
                print(f"[unsync] would unwire hook: PreToolUse -> security_guard.py", flush=True)
        else:
            new_pre.append(block)
    if changed or len(new_pre) < len(pre_list):
        changed = True
        if new_pre:
            hooks["PreToolUse"] = new_pre
        else:
            del hooks["PreToolUse"]

# Remove validate_gate.py from Stop
if "Stop" in hooks:
    stop_list = hooks["Stop"]
    new_stop = []
    stop_changed = False
    for block in stop_list:
        drop = remove_cmd_from_block(block, vg_cmd)
        if drop:
            stop_changed = True
            if dry_run:
                print(f"[unsync] would unwire hook: Stop -> validate_gate.py", flush=True)
        else:
            new_stop.append(block)
    if stop_changed or len(new_stop) < len(stop_list):
        changed = True
        if new_stop:
            hooks["Stop"] = new_stop
        else:
            del hooks["Stop"]

# Drop hooks key if empty
if "hooks" in data and not data["hooks"]:
    del data["hooks"]
    changed = True

if changed and not dry_run:
    # Do NOT create a .bak here — that would cause a re-run to see a .bak with hook
    # entries still present and "restore" them back, breaking idempotency.
    settings_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"[unsync] unwired hooks from {settings_path}", flush=True)
PYEOF
fi

exit $ERRORS
