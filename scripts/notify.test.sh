#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/notify.sh"

WORK="$(mktemp -d /tmp/notifytest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0

# --- shims: a fake tmux + curl on PATH that log their argv ---------------------
BIN="$WORK/bin"; mkdir -p "$BIN"
export TMUX_LOG="$WORK/tmux.log"
export CURL_LOG="$WORK/curl.log"
BELL_FILE="$WORK/bell"
ERR="$WORK/err"

cat > "$BIN/tmux" << 'EOF'
#!/usr/bin/env bash
echo "tmux $*" >> "$TMUX_LOG"
case "$1" in
  display-message) echo "@9" ;;
  show-options)    printf '%s\n' "${SHOW_OPTIONS_RESULT:-}" ;;
esac
exit 0
EOF
chmod +x "$BIN/tmux"

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
assert_not_contains() {  # $1 text, $2 pattern, $3 msg
  if printf '%s' "$1" | grep -qF -- "$2"; then echo "FAIL: $3"; FAILURES=$((FAILURES + 1)); fi
}
assert_lines() {  # $1 file, $2 expected count, $3 msg
  local n; n=$(wc -l < "$1" | tr -d ' ')
  if [ "$n" -ne "$2" ]; then echo "FAIL: $3 (expected $2 lines, got $n)"; FAILURES=$((FAILURES + 1)); fi
}
assert_bell() {    # $1 file, $2 msg — file should be non-empty (only the bell writes there)
  if [ ! -s "$1" ]; then echo "FAIL: $2 (no bell written)"; FAILURES=$((FAILURES + 1)); fi
}
assert_no_bell() { # $1 file, $2 msg
  if [ -s "$1" ]; then echo "FAIL: $2 (bell unexpectedly written)"; FAILURES=$((FAILURES + 1)); fi
}

# --- (b) unconfigured no-op: no TMUX, no NTFY → exit 0, empty stdout+stderr -----
: > "$TMUX_LOG"; : > "$CURL_LOG"
cap env -u TMUX -u NTFY_TOPIC bash "$HOOK" info "T" "M"
assert_rc0   "test(b): unconfigured exits 0"
assert_empty "$OUT" "test(b): unconfigured stdout pure"
assert_empty "$(cat "$ERR")" "test(b): unconfigured stderr empty"

# --- (c) tmux sink (fail): red flag + bell --------------------------------------
: > "$TMUX_LOG"; : > "$CURL_LOG"; rm -f "$BELL_FILE"
cap env -u NTFY_TOPIC TMUX=fake NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" fail "Validate FAIL" "repo: boom"
assert_rc0   "test(c): fail exits 0"
assert_empty "$OUT" "test(c): fail stdout pure"
assert_contains "$(cat "$TMUX_LOG")" "@claude_attention fail" "test(c): fail sets @claude_attention fail"
assert_contains "$(cat "$TMUX_LOG")" "window-status-style"    "test(c): fail sets window-status-style"
assert_contains "$(cat "$TMUX_LOG")" "fg=red,bold"            "test(c): fail flag is red"
assert_bell "$BELL_FILE" "test(c): fail rings the bell"

# --- (d) network sink (fail + pass each push exactly once) -----------------------
: > "$CURL_LOG"
cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" fail "Validate FAIL" "msg-fail"
assert_rc0   "test(d): fail push exits 0"
assert_empty "$OUT" "test(d): fail push stdout pure"
assert_lines "$CURL_LOG" 1 "test(d): fail pushes exactly once"
assert_contains "$(cat "$CURL_LOG")" "Title: Validate FAIL" "test(d): fail push carries title"
assert_contains "$(cat "$CURL_LOG")" "msg-fail"             "test(d): fail push carries message"

: > "$CURL_LOG"
cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" pass "Validate PASS" "branch: PR ready"
assert_lines "$CURL_LOG" 1 "test(d): pass pushes exactly once"
assert_contains "$(cat "$CURL_LOG")" "Title: Validate PASS" "test(d): pass push carries title"
assert_contains "$(cat "$CURL_LOG")" "branch: PR ready"     "test(d): pass push carries message"

# --- (e) info severity: no downgrade of a live red, and never pushes ------------
# e1: window already red → info must NOT write window-status-style, and must NOT push.
: > "$TMUX_LOG"; : > "$CURL_LOG"
cap env TMUX=fake NTFY_TOPIC=t SHOW_OPTIONS_RESULT=fail NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" info "T" "M"
assert_not_contains "$(cat "$TMUX_LOG")" "window-status-style" "test(e1): info does not downgrade a live red"
assert_lines "$CURL_LOG" 0 "test(e1): info never pushes"
# e2: window not red → info sets yellow + @claude_attention info, still no push.
: > "$TMUX_LOG"; : > "$CURL_LOG"
cap env TMUX=fake NTFY_TOPIC=t SHOW_OPTIONS_RESULT= NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" info "T" "M"
assert_contains "$(cat "$TMUX_LOG")" "@claude_attention info" "test(e2): info sets attention info when not red"
assert_contains "$(cat "$TMUX_LOG")" "fg=yellow,bold"         "test(e2): info sets yellow when not red"
assert_lines "$CURL_LOG" 0 "test(e2): info never pushes (not red)"

# --- (f) clear releases the latch: unset both, no bell, no push -----------------
: > "$TMUX_LOG"; : > "$CURL_LOG"; rm -f "$BELL_FILE"
cap env TMUX=fake NTFY_TOPIC=t NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" clear
assert_empty "$OUT" "test(f): clear stdout pure"
assert_contains "$(cat "$TMUX_LOG")" "-u @claude_attention"   "test(f): clear unsets @claude_attention"
assert_contains "$(cat "$TMUX_LOG")" "-u window-status-style" "test(f): clear unsets window-status-style"
assert_no_bell "$BELL_FILE" "test(f): clear does not ring the bell"
assert_lines "$CURL_LOG" 0 "test(f): clear never pushes"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
