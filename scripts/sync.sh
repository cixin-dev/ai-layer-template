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

# Skills and commands use symlinks (not copies) intentionally: edits in the repo
# are immediately visible to Claude Code without re-running sync.sh. The trade-off
# is that they require the repo to be mounted; hooks use copies for resilience instead.
#
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
#   - unreadable src → warn and skip
#   - real directory at dst → warn and skip
#   - real file (not a symlink), executable, identical to src → skip (idempotent)
#   - absent, symlink (including dangling), non-executable, or stale-content copy → copy/refresh
#   - real file with different content → warn of local changes, then overwrite
copy_item() {
  local src="$1" dst="$2"
  if [ ! -r "$src" ]; then
    note "warn: $src is not readable — skipped"
    return
  fi
  if [ -d "$dst" ] && [ ! -L "$dst" ]; then
    note "warn: $dst is a directory — skipped"
    return
  fi
  if [ -f "$dst" ] && [ ! -L "$dst" ] && [ -x "$dst" ] && cmp -s "$src" "$dst"; then
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would copy: $dst <- $src"
  else
    if [ -f "$dst" ] && [ ! -L "$dst" ] && ! cmp -s "$src" "$dst" 2>/dev/null; then
      note "warn: $dst had local changes — overwriting"
    fi
    local tmp
    tmp="${dst}.tmp.$$"
    cp "$src" "$tmp"
    chmod +x "$tmp"
    mv "$tmp" "$dst"
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
# The versioned unattended-autonomy posture, additively merged into live settings.
SHARED_SETTINGS="$REPO_DIR/.claude/settings.shared.json"

if ! command -v python3 >/dev/null 2>&1; then
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would wire hook: PreToolUse -> security_guard.py"
    note "would wire hook: Stop -> validate_gate.py"
    note "would set defaultMode: auto"
    note "would add ask: Bash(git push *)"
    note "would add Notification hook: permission_prompt"
    note "would add Notification hook: idle_prompt"
  else
    note "warn: python3 not found — wire hooks manually by adding to $SETTINGS:"
    note "  PreToolUse: $SG_CMD"
    note "  Stop: $VG_CMD"
    note "  permissions.defaultMode: auto"
    note "  permissions.ask: Bash(git push *)"
    note "  hooks.Notification[permission_prompt]: \"\$HOME/.claude/hooks/notify.sh\" info 'Claude Code' 'Permission needed'"
    note "  hooks.Notification[idle_prompt]: \"\$HOME/.claude/hooks/notify.sh\" info 'Claude Code' 'Waiting for input'"
  fi
else
  python3 - "$SETTINGS" "$SG_CMD" "$VG_CMD" "$DRY_RUN" "$SHARED_SETTINGS" <<'PYEOF'
import json, sys, shutil, pathlib

settings_path = pathlib.Path(sys.argv[1])
sg_cmd = sys.argv[2]
vg_cmd = sys.argv[3]
dry_run = sys.argv[4] == "1"
shared_path = pathlib.Path(sys.argv[5])

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

# The versioned posture file is repo-controlled; an absent file means "no posture".
shared = json.loads(shared_path.read_text()) if shared_path.exists() else {}

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
    isinstance(b, dict) and (
        any(h.get("command") == vg_cmd for h in b.get("hooks", []) if isinstance(h, dict))
        or b.get("command") == vg_cmd
    )
    for b in stop_list
)

# --- Unattended-autonomy posture deltas (from settings.shared.json) ---
shared_perms = shared.get("permissions", {})
shared_default = shared_perms.get("defaultMode")
shared_ask = shared_perms.get("ask", [])
shared_allow = shared_perms.get("allow", [])
shared_notifs = [b for b in shared.get("hooks", {}).get("Notification", []) if isinstance(b, dict)]

live_perms = data.get("permissions", {})
live_default = live_perms.get("defaultMode")
live_ask = live_perms.get("ask", [])
live_allow = live_perms.get("allow", [])

# defaultMode: set only when live has none; warn loudly on ANY non-matching live value
# (the posture silently no-ops under any non-'auto' mode — see grill 2026-06-16).
set_default = shared_default is not None and live_default is None
warn_default = live_default if (shared_default is not None and live_default not in (None, shared_default)) else None

# ask union, graduation-aware: skip an entry the live allow already covers (ADR-0017's
# general invariant) or that live ask already holds.
ask_to_add = [a for a in shared_ask if a not in live_allow and a not in live_ask]
# allow union: preserve-only — add shared allow entries not already live, never remove.
allow_to_add = [a for a in shared_allow if a not in live_allow]
# Notification hooks: dedupe by matcher (command text is cosmetic — grill 2026-06-16).
live_notif_matchers = {
    b.get("matcher") for b in data.get("hooks", {}).get("Notification", []) if isinstance(b, dict)
}
notifs_to_add = [b for b in shared_notifs if b.get("matcher") not in live_notif_matchers]

needs_posture = set_default or bool(ask_to_add) or bool(allow_to_add) or bool(notifs_to_add)

# The loud no-op warning fires in both dry-run and real run, ungated by needs_*.
if warn_default is not None:
    print(f"[sync] ⚠ defaultMode is '{warn_default}', not '{shared_default}' — autonomy posture inactive", flush=True)

if dry_run:
    if needs_pre:
        print(f"[sync] would wire hook: PreToolUse -> security_guard.py", flush=True)
    if needs_stop:
        print(f"[sync] would wire hook: Stop -> validate_gate.py", flush=True)
    if set_default:
        print(f"[sync] would set defaultMode: {shared_default}", flush=True)
    for a in ask_to_add:
        print(f"[sync] would add ask: {a}", flush=True)
    for a in allow_to_add:
        print(f"[sync] would add allow: {a}", flush=True)
    for b in notifs_to_add:
        print(f"[sync] would add Notification hook: {b.get('matcher')}", flush=True)
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
    if needs_posture:
        perms = data.setdefault("permissions", {})
        if set_default:
            perms["defaultMode"] = shared_default
        if ask_to_add:
            perms.setdefault("ask", []).extend(ask_to_add)
        if allow_to_add:
            perms.setdefault("allow", []).extend(allow_to_add)
        if notifs_to_add:
            data.setdefault("hooks", {}).setdefault("Notification", []).extend(notifs_to_add)

    if needs_pre or needs_stop or needs_posture:
        bak_path = pathlib.Path(str(settings_path) + ".bak")
        if settings_path.exists() and not bak_path.exists():
            shutil.copy2(settings_path, bak_path)
        settings_path.write_text(json.dumps(data, indent=2) + "\n")
        if needs_pre:
            print(f"[sync] wired hook: PreToolUse -> security_guard.py", flush=True)
        if needs_stop:
            print(f"[sync] wired hook: Stop -> validate_gate.py", flush=True)
        if set_default:
            print(f"[sync] set defaultMode: {shared_default}", flush=True)
        for a in ask_to_add:
            print(f"[sync] added ask: {a}", flush=True)
        for a in allow_to_add:
            print(f"[sync] added allow: {a}", flush=True)
        for b in notifs_to_add:
            print(f"[sync] added Notification hook: {b.get('matcher')}", flush=True)
PYEOF
fi
