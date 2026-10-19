#!/usr/bin/env bash
# Test seam for launch_guard_check.sh — proves the check flips green->red for the
# RIGHT reason: an unguarded scheduled command inside a ```cron fence fails (rc 1),
# a flock-guarded one passes, a reasoned escape-hatch opts out, a bare (reasonless)
# marker still fails, and out-of-scope launch forms (persistent `&`, cron in prose
# or non-`cron` fences) are not flagged. Mirrors exec_bit_check.test.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/launch_guard_check.sh"

TMPDIR_ROOT="$(mktemp -d /tmp/launchguardtest.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FAILURES=0

init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config core.fileMode false   # match the real NFS checkout
}

# --- 1. known-good: flock-guarded cron line -> pass, rc 0 ---
GOOD="$TMPDIR_ROOT/good"
init_repo "$GOOD"
cat > "$GOOD/runbook.md" <<'MD'
# Runbook
```cron
*/5 * * * * flock -n -E 0 /tmp/ns.lock bash /home/u/ns-drain.sh
```
MD
git -C "$GOOD" add runbook.md
git -C "$GOOD" commit -q -m "guarded cron"
rc=0
out_good="$(cd "$GOOD" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: known-good (flock-guarded) should exit 0, got rc=$rc: $out_good"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_good" | grep -q "launch-guard check passed"; then
  echo "FAIL: known-good missing pass message: $out_good"
  FAILURES=$((FAILURES + 1))
fi

# --- 2. known-bad: unguarded cron line -> fail, rc EXACTLY 1, names the file ---
BAD="$TMPDIR_ROOT/bad"
init_repo "$BAD"
cat > "$BAD/runbook.md" <<'MD'
# Runbook
```cron
*/5 * * * * bash /home/u/ns-drain.sh
```
MD
git -C "$BAD" add runbook.md
git -C "$BAD" commit -q -m "unguarded cron"
rc=0
out_bad="$(cd "$BAD" && bash "$CHECK" 2>&1)" || rc=$?
# Prove it flipped for the RIGHT reason: rc is exactly 1 (the check's own fail
# path), not 127 (missing/broken invocation), and the message names the offender.
if [ "$rc" -ne 1 ]; then
  echo "FAIL: known-bad (unguarded) should exit 1 (check's fail path), got rc=$rc: $out_bad"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_bad" | grep -q "unguarded"; then
  echo "FAIL: known-bad missing the FAIL reason: $out_bad"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_bad" | grep -q "runbook.md"; then
  echo "FAIL: known-bad did not name the offending file: $out_bad"
  FAILURES=$((FAILURES + 1))
fi

# --- 3. escape-hatch WITH reason: reported allowed, rc 0 ---
ALLOW="$TMPDIR_ROOT/allow"
init_repo "$ALLOW"
cat > "$ALLOW/runbook.md" <<'MD'
# Runbook
```cron
# linter:allow-unguarded-cron: single-node dev box, no concurrent drain possible
*/5 * * * * bash /home/u/ns-drain.sh
```
MD
git -C "$ALLOW" add runbook.md
git -C "$ALLOW" commit -q -m "allowed unguarded cron"
rc=0
out_allow="$(cd "$ALLOW" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: reasoned escape-hatch should exit 0, got rc=$rc: $out_allow"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_allow" | grep -qi "allowed"; then
  echo "FAIL: reasoned escape-hatch not reported as allowed: $out_allow"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_allow" | grep -q "single-node dev box"; then
  echo "FAIL: reasoned escape-hatch did not print the reason: $out_allow"
  FAILURES=$((FAILURES + 1))
fi

# --- 4. bare (reasonless) marker must NOT exempt -> rc EXACTLY 1 ---
BAREMARK="$TMPDIR_ROOT/baremark"
init_repo "$BAREMARK"
cat > "$BAREMARK/runbook.md" <<'MD'
# Runbook
```cron
# linter:allow-unguarded-cron
*/5 * * * * bash /home/u/ns-drain.sh
```
MD
git -C "$BAREMARK" add runbook.md
git -C "$BAREMARK" commit -q -m "bare marker unguarded cron"
rc=0
out_baremark="$(cd "$BAREMARK" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 1 ]; then
  echo "FAIL: bare (reasonless) marker must not exempt — should exit 1, got rc=$rc: $out_baremark"
  FAILURES=$((FAILURES + 1))
fi

# --- 5. out-of-scope launches are not candidates -> rc 0 ---
# A persistent single-launch `&` daemon (launched once, can't self-overlap) in a
# ```bash fence, plus an unguarded */5 mentioned in inline prose OUTSIDE any cron
# fence. Neither is inside a ```cron fence, so neither is flagged. Also proves the
# all-*.md scope does not over-reach beyond cron fences (file is named notes.md,
# not "runbook").
OOS="$TMPDIR_ROOT/oos"
init_repo "$OOS"
cat > "$OOS/notes.md" <<'MD'
# Notes (not a runbook)

Persistent single-launch daemon (launched once -> can't self-overlap):
```bash
bash night_shift_loop.sh &
```

An unguarded schedule mentioned in prose, outside any cron fence:
`*/5 * * * * bash ns-drain.sh` — inline prose, not a candidate.
MD
git -C "$OOS" add notes.md
git -C "$OOS" commit -q -m "out of scope launches"
rc=0
out_oos="$(cd "$OOS" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: out-of-scope launches should not be flagged (rc 0), got rc=$rc: $out_oos"
  FAILURES=$((FAILURES + 1))
fi

# --- 6. non-git dir -> skip (fail open), rc 0 ---
NONGIT="$TMPDIR_ROOT/nongit"
mkdir -p "$NONGIT"
rc=0
out_nongit="$(cd "$NONGIT" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: non-git dir should skip (rc 0), got rc=$rc: $out_nongit"
  FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
