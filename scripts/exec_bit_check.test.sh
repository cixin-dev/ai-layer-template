#!/usr/bin/env bash
# Test seam for exec_bit_check.sh — proves the check flips green→red for the
# right reason (a *.sh committed 100644), against known-good and known-bad repos.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/exec_bit_check.sh"

TMPDIR_ROOT="$(mktemp -d /tmp/execbittest.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FAILURES=0

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config core.fileMode false   # match the real NFS checkout
  printf '#!/usr/bin/env bash\necho hi\n' > "$dir/tool.sh"
  git -C "$dir" add tool.sh
}

# --- known-good: tool.sh committed 100755 → pass, rc 0 ---
GOOD="$TMPDIR_ROOT/good"
make_repo "$GOOD"
git -C "$GOOD" update-index --chmod=+x tool.sh
git -C "$GOOD" commit -q -m "add executable tool"
rc=0
out_good="$(cd "$GOOD" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: known-good (100755) should exit 0, got rc=$rc: $out_good"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_good" | grep -q "exec-bit check passed"; then
  echo "FAIL: known-good missing pass message: $out_good"
  FAILURES=$((FAILURES + 1))
fi

# --- known-bad: tool.sh committed 100644 → fail, rc 1, names the file ---
BAD="$TMPDIR_ROOT/bad"
make_repo "$BAD"
git -C "$BAD" update-index --chmod=-x tool.sh
git -C "$BAD" commit -q -m "add non-executable tool"
rc=0
out_bad="$(cd "$BAD" && bash "$CHECK" 2>&1)" || rc=$?
# Prove it flipped for the RIGHT reason: rc is exactly 1 (the check's own fail
# path), not 127 (missing/broken invocation), and the message names the offender.
if [ "$rc" -ne 1 ]; then
  echo "FAIL: known-bad (100644) should exit 1 (check's fail path), got rc=$rc: $out_bad"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_bad" | grep -q "committed non-executable"; then
  echo "FAIL: known-bad missing the FAIL reason: $out_bad"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_bad" | grep -q "tool.sh"; then
  echo "FAIL: known-bad did not name the offending file: $out_bad"
  FAILURES=$((FAILURES + 1))
fi

# --- non-git dir → skip (fail open), rc 0 ---
BARE="$TMPDIR_ROOT/bare"
mkdir -p "$BARE"
rc=0
out_bare="$(cd "$BARE" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: non-git dir should skip (rc 0), got rc=$rc: $out_bare"
  FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
