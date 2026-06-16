#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/notify.sh"

WORK="$(mktemp -d /tmp/notifytest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0

# --- shim: a fake curl on PATH that logs its argv ------------------------------
# notify.sh no longer execs tmux (the window hint is tmux's native bell flag,
# tripped by the BEL we write to NOTIFY_BELL_TARGET), so only curl is shimmed.
BIN="$WORK/bin"; mkdir -p "$BIN"
export CURL_LOG="$WORK/curl.log"
BELL_FILE="$WORK/bell"
ERR="$WORK/err"

cat > "$BIN/curl" << 'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$CURL_LOG"
exit 0
EOF
chmod +x "$BIN/curl"

export PATH="$BIN:$PATH"

# --- helpers -------------------------------------------------------------------
# cap <cmd...> : run, capturing stdout into OUT, stderr into ERR, exit into RC.
cap() { OUT="$("$@" 2>"$ERR")"; RC=$?; }

assert_empty() {  # $1 text, $2 msg
  if [ -n "$1" ]; then echo "FAIL: $2 (stdout not empty: $1)"; FAILURES=$((FAILURES + 1)); fi
}
assert_rc0() {  # $1 msg
  if [ "$RC" -ne 0 ]; then echo "FAIL: $1 (expected RC=0, got $RC)"; FAILURES=$((FAILURES + 1)); fi
}
assert_contains() {  # $1 text, $2 pattern, $3 msg
  if ! printf '%s' "$1" | grep -qF -- "$2"; then echo "FAIL: $3"; FAILURES=$((FAILURES + 1)); fi
}
assert_lines() {  # $1 file, $2 expected count, $3 msg
  local n; n=$(wc -l < "$1" | tr -d ' ')
  if [ "$n" -ne "$2" ]; then echo "FAIL: $3 (expected $2 lines, got $n)"; FAILURES=$((FAILURES + 1)); fi
}
assert_bell() {    # $1 file, $2 msg — file should be non-empty (only the bell writes there)
  if [ ! -s "$1" ]; then echo "FAIL: $2 (no bell written)"; FAILURES=$((FAILURES + 1)); fi
}

# --- (b) unconfigured no-op: no TMUX, no NTFY → exit 0, empty stdout+stderr -----
: > "$CURL_LOG"
cap env -u TMUX -u NTFY_TOPIC bash "$HOOK" info "T" "M"
assert_rc0   "test(b): unconfigured exits 0"
assert_empty "$OUT" "test(b): unconfigured stdout pure"
assert_empty "$(cat "$ERR")" "test(b): unconfigured stderr empty"

# --- (c) tmux transport (fail): rings the bell, sets no window option, stdout pure
: > "$CURL_LOG"; rm -f "$BELL_FILE"
cap env -u NTFY_TOPIC TMUX=fake NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" fail "Validate FAIL" "repo: boom"
assert_rc0   "test(c): fail exits 0"
assert_empty "$OUT" "test(c): fail stdout pure"
assert_bell  "$BELL_FILE" "test(c): fail rings the bell"

# --- (d) network transport: fail + pass each push exactly once, w/ title+message -
: > "$CURL_LOG"
cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" fail "Validate FAIL" "msg-fail"
assert_rc0   "test(d): fail push exits 0"
assert_empty "$OUT" "test(d): fail push stdout pure"
assert_lines "$CURL_LOG" 1 "test(d): fail pushes exactly once"
assert_contains "$(cat "$CURL_LOG")" "Title: Validate FAIL" "test(d): fail push carries title"
assert_contains "$(cat "$CURL_LOG")" "msg-fail"             "test(d): fail push carries message"

: > "$CURL_LOG"; rm -f "$BELL_FILE"
cap env TMUX=fake NTFY_TOPIC=t NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" pass "Validate PASS" "branch: PR ready"
assert_bell  "$BELL_FILE" "test(d): pass also rings the bell"
assert_lines "$CURL_LOG" 1 "test(d): pass pushes exactly once"
assert_contains "$(cat "$CURL_LOG")" "Title: Validate PASS" "test(d): pass push carries title"
assert_contains "$(cat "$CURL_LOG")" "branch: PR ready"     "test(d): pass push carries message"

# --- (e) info: rings the bell (at-keyboard) but NEVER pushes (no phone) ----------
: > "$CURL_LOG"; rm -f "$BELL_FILE"
cap env TMUX=fake NTFY_TOPIC=t NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" info "T" "M"
assert_rc0   "test(e): info exits 0"
assert_empty "$OUT" "test(e): info stdout pure"
assert_bell  "$BELL_FILE" "test(e): info rings the bell"
assert_lines "$CURL_LOG" 0 "test(e): info never pushes"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
