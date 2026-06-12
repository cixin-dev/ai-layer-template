#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SH="$SCRIPT_DIR/sync.sh"

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

REPO="$TMPDIR_ROOT/repo"
CLAUDE_HOME_DIR="$TMPDIR_ROOT/claude_home"

FAILURES=0

assert_contains() {
  local output="$1" pattern="$2" msg="$3"
  if ! printf '%s' "$output" | grep -qF "$pattern"; then
    echo "FAIL: $msg"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_contains() {
  local output="$1" pattern="$2" msg="$3"
  if printf '%s' "$output" | grep -qF "$pattern"; then
    echo "FAIL: $msg"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  if [ ! -e "$path" ]; then
    echo "FAIL: $msg (path not found: $path)"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_file_not_exists() {
  local path="$1" msg="$2"
  if [ -e "$path" ]; then
    echo "FAIL: $msg (path exists but should not: $path)"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_symlink() {
  local path="$1" msg="$2"
  if [ -L "$path" ]; then
    echo "FAIL: $msg (path is a symlink: $path)"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_executable() {
  local path="$1" msg="$2"
  if [ ! -x "$path" ]; then
    echo "FAIL: $msg (path is not executable: $path)"
    FAILURES=$((FAILURES + 1))
  fi
}

setup_fixture() {
  rm -rf "$REPO" "$CLAUDE_HOME_DIR"

  # Repo fixture: three skills, three commands, two hooks, validate.md
  mkdir -p "$REPO/.claude/skills/piv-loop"
  mkdir -p "$REPO/.claude/skills/system-evolution"
  mkdir -p "$REPO/.claude/skills/tdd-gate"
  touch "$REPO/.claude/skills/piv-loop/SKILL.md"
  touch "$REPO/.claude/skills/system-evolution/SKILL.md"
  touch "$REPO/.claude/skills/tdd-gate/SKILL.md"

  mkdir -p "$REPO/.claude/commands"
  touch "$REPO/.claude/commands/plan.md"
  touch "$REPO/.claude/commands/implement.md"
  touch "$REPO/.claude/commands/retroactive.md"
  touch "$REPO/.claude/commands/validate.md"

  mkdir -p "$REPO/.claude/hooks"
  touch "$REPO/.claude/hooks/validate_gate.py"
  touch "$REPO/.claude/hooks/security_guard.py"

  # Claude home fixture: upstream symlinks that must never be touched
  mkdir -p "$CLAUDE_HOME_DIR/skills"
  mkdir -p "$CLAUDE_HOME_DIR/commands"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/grill-with-docs"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/to-prd"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/grill-me"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/to-issues"
}

# --- Test (a): fresh-state dry-run mentions every owned item ---
setup_fixture
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" --dry-run)"

assert_contains "$output" "would link:" "test(a): at least one 'would link:' line"
assert_contains "$output" "piv-loop"        "test(a): piv-loop mentioned"
assert_contains "$output" "system-evolution" "test(a): system-evolution mentioned"
assert_contains "$output" "tdd-gate"         "test(a): tdd-gate mentioned"
assert_contains "$output" "plan.md"          "test(a): plan.md mentioned"
assert_contains "$output" "implement.md"     "test(a): implement.md mentioned"
assert_contains "$output" "retroactive.md"   "test(a): retroactive.md mentioned"

# --- Test (b): idempotency — pre-linked items and pre-wired settings produce no output ---
# Use non-empty content so cmp -s exercises real comparison, not trivially-equal empty files.
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/validate_gate.py"
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/security_guard.py"
# Create correct symlinks first (all owned items, including hooks)
ln -s "$REPO/.claude/skills/piv-loop"          "$CLAUDE_HOME_DIR/skills/piv-loop"
ln -s "$REPO/.claude/skills/system-evolution"  "$CLAUDE_HOME_DIR/skills/system-evolution"
ln -s "$REPO/.claude/skills/tdd-gate"          "$CLAUDE_HOME_DIR/skills/tdd-gate"
ln -s "$REPO/.claude/commands/plan.md"         "$CLAUDE_HOME_DIR/commands/plan.md"
ln -s "$REPO/.claude/commands/implement.md"    "$CLAUDE_HOME_DIR/commands/implement.md"
ln -s "$REPO/.claude/commands/retroactive.md"  "$CLAUDE_HOME_DIR/commands/retroactive.md"
ln -s "$REPO/.claude/commands/validate.md"     "$CLAUDE_HOME_DIR/commands/validate.md"
mkdir -p "$CLAUDE_HOME_DIR/hooks"
ln -s "$REPO/.claude/hooks/validate_gate.py"   "$CLAUDE_HOME_DIR/hooks/validate_gate.py"
ln -s "$REPO/.claude/hooks/security_guard.py"  "$CLAUDE_HOME_DIR/hooks/security_guard.py"
# Wire settings via real run so dry-run below sees them as already wired
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null

output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" --dry-run)"
assert_not_contains "$output" "would link:"     "test(b): no 'would link:' when already linked"
assert_not_contains "$output" "would copy:"     "test(b): no 'would copy:' when hooks already real copies"
assert_not_contains "$output" "would wire hook" "test(b): no 'would wire hook' when settings already wired"

# --- Test (c): upstream safety — upstream names never appear in output ---
setup_fixture  # fresh state (no owned symlinks yet)
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" --dry-run)"

assert_not_contains "$output" "grill-with-docs" "test(c): grill-with-docs not touched"
assert_not_contains "$output" "to-prd"          "test(c): to-prd not touched"
assert_not_contains "$output" "grill-me"        "test(c): grill-me not touched"
assert_not_contains "$output" "to-issues"       "test(c): to-issues not touched"

# --- Test (d): dry-run mentions hook files as 'would copy:' ---
setup_fixture
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" --dry-run)"
assert_contains "$output" "would copy:"       "test(d): 'would copy:' appears in dry-run output"
assert_contains "$output" "validate_gate.py"  "test(d): validate_gate.py mentioned as would copy:"
assert_contains "$output" "security_guard.py" "test(d): security_guard.py mentioned as would copy:"
assert_contains "$output" "validate.md"       "test(d): validate.md mentioned as would link:"

# --- Test (e): dry-run mentions 'would wire hook' for both hooks, leaves no settings.json ---
assert_contains "$output" "would wire hook" "test(e): 'would wire hook' in dry-run output"
assert_contains "$output" "Stop"             "test(e): Stop hook mentioned in dry-run"
assert_contains "$output" "PreToolUse"       "test(e): PreToolUse hook mentioned in dry-run"
assert_file_not_exists "$CLAUDE_HOME_DIR/settings.json" "test(e): dry-run must not create settings.json"

# --- Test (f): real run creates hook copies (real files, executable) and wires settings.json ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
assert_file_exists  "$CLAUDE_HOME_DIR/hooks/validate_gate.py"  "test(f): validate_gate.py created"
assert_not_symlink  "$CLAUDE_HOME_DIR/hooks/validate_gate.py"  "test(f): validate_gate.py is a real file"
assert_executable   "$CLAUDE_HOME_DIR/hooks/validate_gate.py"  "test(f): validate_gate.py is executable"
assert_file_exists  "$CLAUDE_HOME_DIR/hooks/security_guard.py" "test(f): security_guard.py created"
assert_not_symlink  "$CLAUDE_HOME_DIR/hooks/security_guard.py" "test(f): security_guard.py is a real file"
assert_executable   "$CLAUDE_HOME_DIR/hooks/security_guard.py" "test(f): security_guard.py is executable"
assert_file_exists  "$CLAUDE_HOME_DIR/settings.json"           "test(f): settings.json created"
settings_content="$(cat "$CLAUDE_HOME_DIR/settings.json")"
assert_contains "$settings_content" "validate_gate.py"  "test(f): settings.json references validate_gate.py"
assert_contains "$settings_content" "security_guard.py" "test(f): settings.json references security_guard.py"

# --- Test (g): second real run is idempotent (settings.json unchanged, no duplicate entries) ---
sha_before="$(sha256sum "$CLAUDE_HOME_DIR/settings.json" | awk '{print $1}')"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
sha_after="$(sha256sum "$CLAUDE_HOME_DIR/settings.json" | awk '{print $1}')"
if [ "$sha_before" != "$sha_after" ]; then
  echo "FAIL: test(g): settings.json changed on second run (not idempotent)"
  FAILURES=$((FAILURES + 1))
fi
# Count occurrences of each hook command to detect duplicates
vg_count=$(grep -c "validate_gate.py" "$CLAUDE_HOME_DIR/settings.json" || true)
sg_count=$(grep -c "security_guard.py" "$CLAUDE_HOME_DIR/settings.json" || true)
if [ "$vg_count" -ne 1 ]; then
  echo "FAIL: test(g): validate_gate.py appears $vg_count times in settings.json (expected 1)"
  FAILURES=$((FAILURES + 1))
fi
if [ "$sg_count" -ne 1 ]; then
  echo "FAIL: test(g): security_guard.py appears $sg_count times in settings.json (expected 1)"
  FAILURES=$((FAILURES + 1))
fi

# --- Test (h): validate.md appears in dry-run (existing command glob carries the new file) ---
setup_fixture
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" --dry-run)"
assert_contains "$output" "validate.md" "test(h): validate.md appears in dry-run would link:"

# --- Test (i): symlink-into-NFS pre-state becomes real, executable, repo-matching files ---
# Simulates issue #2: machine with old hook symlinks pointing into the NFS share.
setup_fixture
# Populate repo hooks with known content so cmp has something to match.
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/validate_gate.py"
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/security_guard.py"
# Pre-create hook dir with symlinks pointing at a fake "NFS" source (the repo itself).
mkdir -p "$CLAUDE_HOME_DIR/hooks"
ln -s "$REPO/.claude/hooks/validate_gate.py"  "$CLAUDE_HOME_DIR/hooks/validate_gate.py"
ln -s "$REPO/.claude/hooks/security_guard.py" "$CLAUDE_HOME_DIR/hooks/security_guard.py"
# Run sync.sh; it must replace the symlinks with real copies.
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
for hook in validate_gate.py security_guard.py; do
  assert_file_exists "$CLAUDE_HOME_DIR/hooks/$hook" "test(i): $hook exists after migration"
  assert_not_symlink "$CLAUDE_HOME_DIR/hooks/$hook" "test(i): $hook is a real file after migration"
  assert_executable  "$CLAUDE_HOME_DIR/hooks/$hook" "test(i): $hook is executable after migration"
  if ! cmp -s "$REPO/.claude/hooks/$hook" "$CLAUDE_HOME_DIR/hooks/$hook"; then
    echo "FAIL: test(i): $hook contents do not match repo source after migration"
    FAILURES=$((FAILURES + 1))
  fi
done

# --- Test (j): chmod -x on installed hook is repaired by next sync ---
setup_fixture
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/validate_gate.py"
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/security_guard.py"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
chmod -x "$CLAUDE_HOME_DIR/hooks/validate_gate.py"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
assert_executable "$CLAUDE_HOME_DIR/hooks/validate_gate.py" "test(j): chmod -x on installed hook repaired by next sync"

# --- Test (k): user-modified hook content → sync warns before overwriting ---
setup_fixture
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/validate_gate.py"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
echo '# user addition' >> "$CLAUDE_HOME_DIR/hooks/validate_gate.py"
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH")"
assert_contains "$output" "warn" "test(k): warns when overwriting user-modified hook"

# --- Test (l): unreadable src → sync warns, skips, preserves dst, script continues ---
setup_fixture
echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/validate_gate.py"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
chmod 000 "$REPO/.claude/hooks/validate_gate.py"
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" 2>&1)" || true
chmod 644 "$REPO/.claude/hooks/validate_gate.py"
assert_contains "$output" "warn" "test(l): warns when src is unreadable"
assert_file_exists "$CLAUDE_HOME_DIR/hooks/validate_gate.py" "test(l): dst preserved when src unreadable"
assert_file_exists "$CLAUDE_HOME_DIR/hooks/security_guard.py" "test(l): other hooks still installed when one src unreadable"

# --- Test (m): directory at dst → sync warns, skips, script continues, other hooks installed ---
setup_fixture
mkdir -p "$CLAUDE_HOME_DIR/hooks/validate_gate.py"
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" 2>&1)" || true
assert_contains "$output" "warn" "test(m): warns when dst is a directory"
assert_file_exists "$CLAUDE_HOME_DIR/hooks/security_guard.py" "test(m): other hooks installed when one dst is a directory"

# --- Test (n): flat-format Stop entry already present → sync does not add a duplicate ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
# Convert the nested Stop entry to flat format: {"command": "..."} without a "hooks" wrapper.
python3 - "$CLAUDE_HOME_DIR/settings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.loads(open(path).read())
stop_list = data.get("hooks", {}).get("Stop", [])
flat = []
for b in stop_list:
    if isinstance(b, dict) and isinstance(b.get("hooks"), list):
        for h in b["hooks"]:
            if isinstance(h, dict) and "command" in h:
                flat.append({"command": h["command"]})
    else:
        flat.append(b)
data["hooks"]["Stop"] = flat
open(path, "w").write(json.dumps(data, indent=2) + "\n")
PYEOF
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" --dry-run)"
assert_not_contains "$output" "would wire hook: Stop" "test(n): flat-format Stop entry recognized — no duplicate wired"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
