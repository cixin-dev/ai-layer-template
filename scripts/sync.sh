#!/usr/bin/env bash
set -euo pipefail

# Symlink each owned skill/command into ~/.claude/{skills,commands}/; copy hooks
# into ~/.claude/hooks/ as real files (so they survive an unmounted NFS share).
# Owned items are discovered dynamically from this repo's .claude/ tree.
# Also additively wires the two hook entries into ~/.claude/settings.json
# (backs up the file first; idempotent; never removes user keys).
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
  mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/hooks"
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

# Copy a single hook file. Policy:
#   - real file (not a symlink) identical to src → skip (idempotent)
#   - absent, a symlink (including dangling), or stale-content copy → copy/refresh
copy_item() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would copy: $dst <- $src"
  else
    rm -f "$dst"
    cp "$src" "$dst"
    chmod +x "$dst"
    note "copied: $dst <- $src"
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

# Hooks: each file under .claude/hooks/
hooks_src="$REPO_DIR/.claude/hooks"
if [ -d "$hooks_src" ]; then
  for hook_file in "$hooks_src"/*; do
    [ -f "$hook_file" ] || continue
    name="$(basename "$hook_file")"
    copy_item "$hooks_src/$name" "$CLAUDE_DIR/hooks/$name"
  done
fi

# Wire hook entries into settings.json (additive, idempotent, backed-up).
# Uses python3 (already required by the hooks). Fails open with a manual
# snippet if python3 is missing or the file is unparseable.
SETTINGS="$CLAUDE_DIR/settings.json"
SG_CMD="python3 \"$CLAUDE_DIR/hooks/security_guard.py\""
VG_CMD="python3 \"$CLAUDE_DIR/hooks/validate_gate.py\""

if ! command -v python3 >/dev/null 2>&1; then
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would wire hook: PreToolUse -> security_guard.py"
    note "would wire hook: Stop -> validate_gate.py"
  else
    note "warn: python3 not found — wire hooks manually by adding to $SETTINGS:"
    note "  PreToolUse: $SG_CMD"
    note "  Stop: $VG_CMD"
  fi
else
  python3 - "$SETTINGS" "$SG_CMD" "$VG_CMD" "$DRY_RUN" <<'PYEOF'
import json, sys, shutil, pathlib

settings_path = pathlib.Path(sys.argv[1])
sg_cmd = sys.argv[2]
vg_cmd = sys.argv[3]
dry_run = sys.argv[4] == "1"

try:
    data = json.loads(settings_path.read_text()) if settings_path.exists() else {}
except Exception as e:
    if dry_run:
        print(f"[sync] warn: could not read {settings_path} — assuming hooks not wired", flush=True)
        print(f"[sync] would wire hook: PreToolUse -> security_guard.py", flush=True)
        print(f"[sync] would wire hook: Stop -> validate_gate.py", flush=True)
    else:
        print(f"[sync] warn: could not parse {settings_path}: {e} — wire hooks manually", flush=True)
        print(f"[sync]   PreToolUse: {sg_cmd}", flush=True)
        print(f"[sync]   Stop: {vg_cmd}", flush=True)
    sys.exit(0)

hooks = data.get("hooks", {})

# Determine what needs wiring.
sg_matcher = "Bash|Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Grep"
sg_entry = {"type": "command", "command": sg_cmd}
pre_list = hooks.get("PreToolUse", [])
existing_pre = next((b for b in pre_list if isinstance(b, dict) and b.get("matcher") == sg_matcher), None)
if existing_pre is None:
    needs_pre = True
elif isinstance(existing_pre.get("hooks"), list):
    needs_pre = not any(h.get("command") == sg_cmd for h in existing_pre["hooks"] if isinstance(h, dict))
else:
    # Non-standard flat format: check top-level command field to avoid false add
    needs_pre = existing_pre.get("command") != sg_cmd

vg_entry = {"type": "command", "command": vg_cmd}
stop_list = hooks.get("Stop", [])
needs_stop = not any(
    isinstance(b, dict) and any(h.get("command") == vg_cmd for h in b.get("hooks", []) if isinstance(h, dict))
    for b in stop_list
)

if dry_run:
    if needs_pre:
        print(f"[sync] would wire hook: PreToolUse -> security_guard.py", flush=True)
    if needs_stop:
        print(f"[sync] would wire hook: Stop -> validate_gate.py", flush=True)
else:
    if needs_pre:
        hooks_section = data.setdefault("hooks", {})
        pre_list_rw = hooks_section.setdefault("PreToolUse", [])
        if existing_pre is None:
            pre_list_rw.append({"matcher": sg_matcher, "hooks": [sg_entry]})
        elif isinstance(existing_pre.get("hooks"), list):
            existing_pre["hooks"].append(sg_entry)
        else:
            # Flat-format block owned by someone else — append our own block
            pre_list_rw.append({"matcher": sg_matcher, "hooks": [sg_entry]})
    if needs_stop:
        hooks_section = data.setdefault("hooks", {})
        hooks_section.setdefault("Stop", []).append({"hooks": [vg_entry]})

    if needs_pre or needs_stop:
        bak_path = pathlib.Path(str(settings_path) + ".bak")
        if settings_path.exists() and not bak_path.exists():
            shutil.copy2(settings_path, bak_path)
        settings_path.write_text(json.dumps(data, indent=2) + "\n")
        if needs_pre:
            print(f"[sync] wired hook: PreToolUse -> security_guard.py", flush=True)
        if needs_stop:
            print(f"[sync] wired hook: Stop -> validate_gate.py", flush=True)
PYEOF
fi
