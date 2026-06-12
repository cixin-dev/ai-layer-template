#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SH="$SCRIPT_DIR/sync.sh"
UNSYNC_SH="$SCRIPT_DIR/unsync.sh"

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
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
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
  echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/validate_gate.py"
  echo '#!/usr/bin/env python3' > "$REPO/.claude/hooks/security_guard.py"

  # Claude home fixture: upstream symlinks that must never be touched
  mkdir -p "$CLAUDE_HOME_DIR/skills"
  mkdir -p "$CLAUDE_HOME_DIR/commands"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/grill-with-docs"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/to-prd"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/grill-me"
  ln -s /upstream/placeholder "$CLAUDE_HOME_DIR/skills/to-issues"
}

# --- Test (a): dry-run is read-only ---
# After a real sync.sh, unsync.sh --dry-run prints what would happen but changes nothing.
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" --dry-run)"
assert_contains "$output" "would remove" "test(a): 'would remove' appears in dry-run output"
assert_contains "$output" "piv-loop"    "test(a): piv-loop mentioned in dry-run"
assert_file_exists "$CLAUDE_HOME_DIR/skills/piv-loop"        "test(a): piv-loop symlink still exists after dry-run"
assert_file_exists "$CLAUDE_HOME_DIR/hooks/validate_gate.py" "test(a): validate_gate.py still exists after dry-run"
assert_file_exists "$CLAUDE_HOME_DIR/settings.json"          "test(a): settings.json still exists after dry-run"

# --- Test (b): idempotency — second run produces no removed/unwired lines and exits 0 ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
exit_code=0
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH")" || exit_code=$?
assert_not_contains "$output" "removed symlink:" "test(b): no 'removed symlink:' on second run"
assert_not_contains "$output" "removed hook:"    "test(b): no 'removed hook:' on second run"
assert_not_contains "$output" "unwired hooks"    "test(b): no 'unwired hooks' on second run"
if [ "$exit_code" -ne 0 ]; then
  echo "FAIL: test(b): second run exited $exit_code (expected 0)"
  FAILURES=$((FAILURES + 1))
fi

# --- Test (c): upstream safety — upstream symlinks never mentioned or touched ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH")"
assert_not_contains "$output" "grill-with-docs" "test(c): grill-with-docs not touched"
assert_not_contains "$output" "to-prd"          "test(c): to-prd not touched"
assert_not_contains "$output" "grill-me"        "test(c): grill-me not touched"
assert_not_contains "$output" "to-issues"       "test(c): to-issues not touched"
assert_file_exists "$CLAUDE_HOME_DIR/skills/grill-with-docs" "test(c): grill-with-docs still exists"
assert_file_exists "$CLAUDE_HOME_DIR/skills/to-prd"          "test(c): to-prd still exists"
assert_file_exists "$CLAUDE_HOME_DIR/skills/grill-me"        "test(c): grill-me still exists"
assert_file_exists "$CLAUDE_HOME_DIR/skills/to-issues"       "test(c): to-issues still exists"

# --- Test (d): removes owned symlinks ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
assert_file_not_exists "$CLAUDE_HOME_DIR/skills/piv-loop"       "test(d): piv-loop symlink removed"
assert_file_not_exists "$CLAUDE_HOME_DIR/skills/system-evolution" "test(d): system-evolution symlink removed"
assert_file_not_exists "$CLAUDE_HOME_DIR/skills/tdd-gate"       "test(d): tdd-gate symlink removed"
assert_file_not_exists "$CLAUDE_HOME_DIR/commands/plan.md"      "test(d): plan.md symlink removed"
assert_file_not_exists "$CLAUDE_HOME_DIR/commands/implement.md" "test(d): implement.md symlink removed"
assert_file_not_exists "$CLAUDE_HOME_DIR/commands/validate.md"  "test(d): validate.md symlink removed"
# Upstream symlinks survive
assert_file_exists "$CLAUDE_HOME_DIR/skills/grill-with-docs" "test(d): grill-with-docs untouched"
assert_file_exists "$CLAUDE_HOME_DIR/skills/to-prd"          "test(d): to-prd untouched"

# --- Test (e): removes hook copies ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
assert_file_not_exists "$CLAUDE_HOME_DIR/hooks/validate_gate.py"  "test(e): validate_gate.py removed"
assert_file_not_exists "$CLAUDE_HOME_DIR/hooks/security_guard.py" "test(e): security_guard.py removed"

# --- Test (f): restore from .bak ---
# Pre-create settings.json with a user key so sync.sh writes a .bak.
setup_fixture
echo '{"theme":"dark"}' > "$CLAUDE_HOME_DIR/settings.json"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
settings_content="$(cat "$CLAUDE_HOME_DIR/settings.json")"
assert_not_contains "$settings_content" "security_guard.py" "test(f): security_guard.py not in restored settings.json"
assert_not_contains "$settings_content" "validate_gate.py"  "test(f): validate_gate.py not in restored settings.json"
assert_contains     "$settings_content" "dark"              "test(f): user theme key preserved in restored settings.json"
assert_file_not_exists "$CLAUDE_HOME_DIR/settings.json.bak" "test(f): .bak is gone after restore"

# --- Test (g): surgical removal (no .bak) ---
# Fresh fixture, no pre-existing settings.json → sync.sh writes no .bak.
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
assert_file_not_exists "$CLAUDE_HOME_DIR/settings.json.bak" "test(g): no .bak created when settings.json didn't pre-exist"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
settings_content="$(cat "$CLAUDE_HOME_DIR/settings.json")"
if grep -qF "security_guard.py" "$CLAUDE_HOME_DIR/settings.json" 2>/dev/null; then
  echo "FAIL: test(g): security_guard.py still in settings.json after surgical removal"
  FAILURES=$((FAILURES + 1))
fi
if grep -qF "validate_gate.py" "$CLAUDE_HOME_DIR/settings.json" 2>/dev/null; then
  echo "FAIL: test(g): validate_gate.py still in settings.json after surgical removal"
  FAILURES=$((FAILURES + 1))
fi
assert_file_not_exists "$CLAUDE_HOME_DIR/settings.json.bak" "test(g): no .bak created by surgical removal"
# Second run is idempotent and exits 0 — no hook-entry resurrection
exit_code2=0
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null || exit_code2=$?
if [ "$exit_code2" -ne 0 ]; then
  echo "FAIL: test(g): second surgical run exited $exit_code2 (expected 0)"
  FAILURES=$((FAILURES + 1))
fi
if grep -qF "security_guard.py" "$CLAUDE_HOME_DIR/settings.json" 2>/dev/null; then
  echo "FAIL: test(g): security_guard.py resurrected after second surgical run"
  FAILURES=$((FAILURES + 1))
fi

# --- Test (h): unexpected state — directory at a hook path ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
# Replace validate_gate.py with a directory to simulate unexpected state.
rm "$CLAUDE_HOME_DIR/hooks/validate_gate.py"
mkdir "$CLAUDE_HOME_DIR/hooks/validate_gate.py"
exit_code_h=0
output_h="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" 2>&1)" || exit_code_h=$?
if [ "$exit_code_h" -eq 0 ]; then
  echo "FAIL: test(h): unsync.sh exited 0 when hook was a directory (expected non-zero)"
  FAILURES=$((FAILURES + 1))
fi
assert_contains "$output_h" "unexpected state" "test(h): output contains 'unexpected state' message"
# Other hook was still removed
assert_file_not_exists "$CLAUDE_HOME_DIR/hooks/security_guard.py" "test(h): security_guard.py still removed despite directory error"
# Cleanup the directory we created
rmdir "$CLAUDE_HOME_DIR/hooks/validate_gate.py"

# --- Test (i): preserve user real file at an owned path ---
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
# Replace the owned plan.md symlink with a real user file
rm "$CLAUDE_HOME_DIR/commands/plan.md"
echo "user content" > "$CLAUDE_HOME_DIR/commands/plan.md"
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
assert_file_exists "$CLAUDE_HOME_DIR/commands/plan.md" "test(i): real user file at owned path preserved"

# --- Test (j): cross-mount — sync from REPO, unsync from REPO2 (different path, same .claude/ layout) ---
setup_fixture
REPO2="$TMPDIR_ROOT/repo2"
mkdir -p "$REPO2/.claude/skills/piv-loop" \
          "$REPO2/.claude/skills/system-evolution" \
          "$REPO2/.claude/skills/tdd-gate" \
          "$REPO2/.claude/commands" \
          "$REPO2/.claude/hooks"
touch "$REPO2/.claude/skills/piv-loop/SKILL.md" \
      "$REPO2/.claude/skills/system-evolution/SKILL.md" \
      "$REPO2/.claude/skills/tdd-gate/SKILL.md" \
      "$REPO2/.claude/commands/plan.md" \
      "$REPO2/.claude/commands/implement.md" \
      "$REPO2/.claude/commands/retroactive.md" \
      "$REPO2/.claude/commands/validate.md"
echo '#!/usr/bin/env python3' > "$REPO2/.claude/hooks/validate_gate.py"
echo '#!/usr/bin/env python3' > "$REPO2/.claude/hooks/security_guard.py"
# Sync from REPO1, unsync from REPO2 — simulates NFS vs local checkout
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
SYNC_REPO_DIR="$REPO2" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
assert_file_not_exists "$CLAUDE_HOME_DIR/skills/piv-loop"         "test(j): piv-loop removed (cross-mount)"
assert_file_not_exists "$CLAUDE_HOME_DIR/skills/system-evolution" "test(j): system-evolution removed (cross-mount)"
assert_file_not_exists "$CLAUDE_HOME_DIR/skills/tdd-gate"         "test(j): tdd-gate removed (cross-mount)"
assert_file_not_exists "$CLAUDE_HOME_DIR/commands/plan.md"        "test(j): plan.md removed (cross-mount)"
assert_file_not_exists "$CLAUDE_HOME_DIR/commands/implement.md"   "test(j): implement.md removed (cross-mount)"
assert_file_exists "$CLAUDE_HOME_DIR/skills/grill-with-docs" "test(j): grill-with-docs untouched (cross-mount)"
assert_file_exists "$CLAUDE_HOME_DIR/skills/to-prd"          "test(j): to-prd untouched (cross-mount)"
assert_file_exists "$CLAUDE_HOME_DIR/skills/grill-me"        "test(j): grill-me untouched (cross-mount)"
assert_file_exists "$CLAUDE_HOME_DIR/skills/to-issues"       "test(j): to-issues untouched (cross-mount)"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
