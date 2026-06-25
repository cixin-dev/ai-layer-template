#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMINDER="$SCRIPT_DIR/doc_change_reminder.sh"

TMPDIR_ROOT="$(mktemp -d /tmp/dcrtest.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FAILURES=0

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) echo "FAIL: $msg (expected output to contain '$needle')"; FAILURES=$((FAILURES + 1)) ;;
  esac
}

assert_absent() {
  local haystack="$1" needle="$2" msg="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $msg (expected output NOT to contain '$needle')"; FAILURES=$((FAILURES + 1)) ;;
    *) ;;
  esac
}

assert_exit0() {
  local ec="$1" msg="$2"
  if [ "$ec" -ne 0 ]; then
    echo "FAIL: $msg (expected exit 0, got $ec)"; FAILURES=$((FAILURES + 1))
  fi
}

# Build a throwaway repo with a `main` baseline and a feature branch.
# $1 = repo dir, $2 = file to touch on the feature branch.
make_repo() {
  local dir="$1" file="$2"
  mkdir -p "$dir"
  (
    cd "$dir"
    git init -q -b main
    git config user.email t@t.t && git config user.name t
    mkdir -p docs/adr
    echo "seed" > README.md
    git add -A && git commit -qm seed
    git checkout -q -b feature
    mkdir -p "$(dirname "$file")"
    echo "change" >> "$file"
    git add -A && git commit -qm change
  )
}

NEEDLE="[doc-change-reminder]"

# --- Test (1): branch touches CONTEXT.md → reminder printed, exit 0 ---
R1="$TMPDIR_ROOT/r1"; make_repo "$R1" "CONTEXT.md"
ec=0; out=$( cd "$R1" && bash "$REMINDER" 2>&1 ) || ec=$?
assert_exit0 "$ec" "test(1): exits 0"
assert_contains "$out" "$NEEDLE" "test(1): CONTEXT.md touched → reminder shown"

# --- Test (2): branch touches docs/adr/* → reminder printed ---
R2="$TMPDIR_ROOT/r2"; make_repo "$R2" "docs/adr/0099-foo.md"
ec=0; out=$( cd "$R2" && bash "$REMINDER" 2>&1 ) || ec=$?
assert_exit0 "$ec" "test(2): exits 0"
assert_contains "$out" "$NEEDLE" "test(2): docs/adr touched → reminder shown"

# --- Test (3): branch touches only non-canonical files → no reminder ---
R3="$TMPDIR_ROOT/r3"; make_repo "$R3" "scripts/foo.sh"
ec=0; out=$( cd "$R3" && bash "$REMINDER" 2>&1 ) || ec=$?
assert_exit0 "$ec" "test(3): exits 0"
assert_absent "$out" "$NEEDLE" "test(3): non-canonical only → no reminder"

# --- Test (4): on the default branch → no reminder ---
R4="$TMPDIR_ROOT/r4"; make_repo "$R4" "CONTEXT.md"
ec=0; out=$( cd "$R4" && git checkout -q main && bash "$REMINDER" 2>&1 ) || ec=$?
assert_exit0 "$ec" "test(4): exits 0"
assert_absent "$out" "$NEEDLE" "test(4): on main → no reminder"

# --- Test (5): not a git repo → silent, exit 0 ---
R5="$TMPDIR_ROOT/r5"; mkdir -p "$R5"
ec=0; out=$( cd "$R5" && bash "$REMINDER" 2>&1 ) || ec=$?
assert_exit0 "$ec" "test(5): exits 0 outside a repo"
assert_absent "$out" "$NEEDLE" "test(5): outside a repo → no reminder"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
