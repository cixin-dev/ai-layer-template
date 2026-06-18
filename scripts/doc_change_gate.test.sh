#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/doc_change_gate.sh"

TMPDIR_ROOT="$(mktemp -d /tmp/dgtest.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FAILURES=0

assert_pass() {
  local exit_code="$1" msg="$2"
  if [ "$exit_code" -ne 0 ]; then
    echo "FAIL: $msg (expected exit 0, got $exit_code)"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_fail() {
  local exit_code="$1" msg="$2"
  if [ "$exit_code" -eq 0 ]; then
    echo "FAIL: $msg (expected non-zero exit, got 0)"
    FAILURES=$((FAILURES + 1))
  fi
}

make_files() {
  local path="$1"; shift
  printf '%s\n' "$@" > "$path"
}

# --- Test (1): no canonical changes → pass ---
FILES_1="$TMPDIR_ROOT/files1.txt"
BODY_1="$TMPDIR_ROOT/body1.txt"
make_files "$FILES_1" "scripts/foo.sh" "README.md"
printf 'Some PR body without a TC section.' > "$BODY_1"
ec=0; bash "$GATE" "$FILES_1" "$BODY_1" 2>/dev/null || ec=$?
assert_pass $ec "test(1): no canonical changes → pass"

# --- Test (2): CONTEXT.md + qualified TC body → pass ---
FILES_2="$TMPDIR_ROOT/files2.txt"
BODY_2="$TMPDIR_ROOT/body2.txt"
make_files "$FILES_2" "CONTEXT.md"
cat > "$BODY_2" << 'EOF'
## 變更說明

新增「誤路由」一詞：feature idea 走 strategic-planning，不走 grill-with-docs。
EOF
ec=0; bash "$GATE" "$FILES_2" "$BODY_2" 2>/dev/null || ec=$?
assert_pass $ec "test(2): CONTEXT.md + qualified TC body → pass"

# --- Test (3): CONTEXT.md + empty body → fail ---
FILES_3="$TMPDIR_ROOT/files3.txt"
BODY_3="$TMPDIR_ROOT/body3.txt"
make_files "$FILES_3" "CONTEXT.md"
printf '' > "$BODY_3"
ec=0; bash "$GATE" "$FILES_3" "$BODY_3" 2>/dev/null || ec=$?
assert_fail $ec "test(3): CONTEXT.md + empty body → fail"

# --- Test (4): docs/adr/* + English-only body → fail ---
FILES_4="$TMPDIR_ROOT/files4.txt"
BODY_4="$TMPDIR_ROOT/body4.txt"
make_files "$FILES_4" "docs/adr/0022-foo.md"
cat > "$BODY_4" << 'EOF'
## Change Notes

Added a new ADR documenting the comprehension boundary decision.
EOF
ec=0; bash "$GATE" "$FILES_4" "$BODY_4" 2>/dev/null || ec=$?
assert_fail $ec "test(4): docs/adr/* + English-only body → fail"

# --- Test (5): docs/adr/* + qualified TC body → pass ---
FILES_5="$TMPDIR_ROOT/files5.txt"
BODY_5="$TMPDIR_ROOT/body5.txt"
make_files "$FILES_5" "docs/adr/0022-foo.md"
cat > "$BODY_5" << 'EOF'
## 變更說明

ADR-0022 記錄「canonical 文件留英文、繁中理解層只在 ephemeral 表面」的決定。
EOF
ec=0; bash "$GATE" "$FILES_5" "$BODY_5" 2>/dev/null || ec=$?
assert_pass $ec "test(5): docs/adr/* + qualified TC body → pass"

# --- Test (6): CONTEXT.md + bare heading only (no TC content below) → fail ---
FILES_6="$TMPDIR_ROOT/files6.txt"
BODY_6="$TMPDIR_ROOT/body6.txt"
make_files "$FILES_6" "CONTEXT.md"
printf '## 變更說明\n' > "$BODY_6"
ec=0; bash "$GATE" "$FILES_6" "$BODY_6" 2>/dev/null || ec=$?
assert_fail $ec "test(6): bare heading only (no TC content) → fail"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
