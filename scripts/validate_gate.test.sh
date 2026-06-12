#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/validate_gate.py"

TMPDIR_ROOT="$(mktemp -d /tmp/vgtest.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

RAN_LOG="$TMPDIR_ROOT/ran.log"
STDERR_FILE="$TMPDIR_ROOT/stderr"

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

# Creates <dir>/.claude/validate.sh that appends the tree path to ran.log and exits <exit_code>.
make_tree() {
  local dir="$1" exit_code="$2"
  local ran_log="$RAN_LOG"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/validate.sh" << SCRIPT
#!/usr/bin/env bash
echo "$dir" >> "$ran_log"
exit $exit_code
SCRIPT
  chmod +x "$dir/.claude/validate.sh"
}

reset_runlog() {
  rm -f "$RAN_LOG"
}

# --- Test (a): worktree cwd wins (the bug) ---
# MAIN green, WORKTREE red; payload cwd = WORKTREE.
# Current hook (CLAUDE_PROJECT_DIR path): runs MAIN (green) → no block → FAIL.
# Fixed hook: walks up from WORKTREE, finds WORKTREE's validate.sh → block.
MAIN_A="$TMPDIR_ROOT/main_a"
WORKTREE_A="$TMPDIR_ROOT/worktree_a"
make_tree "$MAIN_A" 0
make_tree "$WORKTREE_A" 1
reset_runlog
payload_a='{"cwd": "'"$WORKTREE_A"'"}'
stdout_a="$(printf '%s' "$payload_a" | CLAUDE_PROJECT_DIR="$MAIN_A" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_contains     "$stdout_a"                                   '"decision": "block"' "test(a): worktree red blocks"
assert_contains     "$(cat "$RAN_LOG" 2>/dev/null || true)"       "$WORKTREE_A"        "test(a): worktree validate.sh ran"
assert_not_contains "$(cat "$RAN_LOG" 2>/dev/null || true)"       "$MAIN_A"            "test(a): main validate.sh did not run"

# --- Test (b): main-repo green unchanged ---
MAIN_B="$TMPDIR_ROOT/main_b"
make_tree "$MAIN_B" 0
reset_runlog
payload_b='{"cwd": "'"$MAIN_B"'"}'
stdout_b="$(printf '%s' "$payload_b" | CLAUDE_PROJECT_DIR="$MAIN_B" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_not_contains "$stdout_b"                                   '"decision": "block"' "test(b): main-repo green passes"
assert_contains     "$(cat "$RAN_LOG" 2>/dev/null || true)"       "$MAIN_B"            "test(b): main validate.sh ran"

# --- Test (c): main-repo red still blocks (regression guard) ---
MAIN_C="$TMPDIR_ROOT/main_c"
make_tree "$MAIN_C" 1
reset_runlog
payload_c='{"cwd": "'"$MAIN_C"'"}'
stdout_c="$(printf '%s' "$payload_c" | CLAUDE_PROJECT_DIR="$MAIN_C" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_contains "$stdout_c" '"decision": "block"' "test(c): main-repo red blocks"

# --- Test (d): subdir of worktree (walk-up) ---
# Walk starts from WORKTREE/src/deep, must climb to WORKTREE and find its validate.sh.
# Current hook: uses MAIN_D (green) → no block → FAIL.
MAIN_D="$TMPDIR_ROOT/main_d"
WORKTREE_D="$TMPDIR_ROOT/worktree_d"
make_tree "$MAIN_D" 0
make_tree "$WORKTREE_D" 1
subdir_d="$WORKTREE_D/src/deep"
mkdir -p "$subdir_d"
reset_runlog
payload_d='{"cwd": "'"$subdir_d"'"}'
stdout_d="$(printf '%s' "$payload_d" | CLAUDE_PROJECT_DIR="$MAIN_D" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_contains     "$stdout_d"                                   '"decision": "block"' "test(d): subdir walk-up blocks"
assert_contains     "$(cat "$RAN_LOG" 2>/dev/null || true)"       "$WORKTREE_D"        "test(d): worktree validate.sh ran"

# --- Test (e): no cwd in payload → env fallback ---
MAIN_E="$TMPDIR_ROOT/main_e"
make_tree "$MAIN_E" 1
reset_runlog
payload_e='{}'
stdout_e="$(printf '%s' "$payload_e" | CLAUDE_PROJECT_DIR="$MAIN_E" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_contains "$stdout_e" '"decision": "block"' "test(e): no cwd falls back to env, blocks on red"

# --- Test (f): cwd tree has no validate.sh → env fallback ---
# Bare dir has no .claude/ anywhere up to filesystem root (/tmp is outside $HOME).
MAIN_F="$TMPDIR_ROOT/main_f"
BARE_F="$TMPDIR_ROOT/bare_f"
make_tree "$MAIN_F" 1
mkdir -p "$BARE_F"
reset_runlog
payload_f='{"cwd": "'"$BARE_F"'"}'
stdout_f="$(printf '%s' "$payload_f" | CLAUDE_PROJECT_DIR="$MAIN_F" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_contains "$stdout_f" '"decision": "block"' "test(f): cwd with no validate.sh falls back to env, blocks"

# --- Test (g): fail open — nothing resolvable ---
BARE_G="$TMPDIR_ROOT/bare_g"
mkdir -p "$BARE_G"
reset_runlog
payload_g='{"cwd": "'"$BARE_G"'"}'
stdout_g="$(printf '%s' "$payload_g" | env -u CLAUDE_PROJECT_DIR python3 "$HOOK" 2>"$STDERR_FILE")"
assert_not_contains "$stdout_g"              '"decision": "block"' "test(g): nothing resolvable, fail open"
assert_contains     "$(cat "$STDERR_FILE")"  "skipping"            "test(g): stderr mentions skipping"

# --- Test (h): fail open — unparsable stdin ---
reset_runlog
stdout_h="$(printf 'not json' | python3 "$HOOK" 2>"$STDERR_FILE")"
assert_not_contains "$stdout_h"             '"decision": "block"' "test(h): unparsable stdin, fail open"
assert_contains     "$(cat "$STDERR_FILE")" "Could not parse"     "test(h): stderr mentions Could not parse"

# --- Test (i): fail open — stop_hook_active ---
WORKTREE_I="$TMPDIR_ROOT/worktree_i"
make_tree "$WORKTREE_I" 1
reset_runlog
payload_i='{"stop_hook_active": true, "cwd": "'"$WORKTREE_I"'"}'
stdout_i="$(printf '%s' "$payload_i" | CLAUDE_PROJECT_DIR="$WORKTREE_I" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_not_contains "$stdout_i"  '"decision": "block"' "test(i): stop_hook_active, fail open"
assert_file_not_exists "$RAN_LOG" "test(i): validate.sh never ran (ran.log absent)"

# --- Test (j): fail open — timeout ---
WORKTREE_J="$TMPDIR_ROOT/worktree_j"
mkdir -p "$WORKTREE_J/.claude"
cat > "$WORKTREE_J/.claude/validate.sh" << 'SCRIPT'
#!/usr/bin/env bash
sleep 5
SCRIPT
chmod +x "$WORKTREE_J/.claude/validate.sh"
reset_runlog
payload_j='{"cwd": "'"$WORKTREE_J"'"}'
stdout_j="$(printf '%s' "$payload_j" | VALIDATE_GATE_TIMEOUT=1 CLAUDE_PROJECT_DIR="$WORKTREE_J" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_not_contains "$stdout_j"             '"decision": "block"' "test(j): timeout, fail open"
assert_contains     "$(cat "$STDERR_FILE")" "timed out"           "test(j): stderr mentions timed out"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
