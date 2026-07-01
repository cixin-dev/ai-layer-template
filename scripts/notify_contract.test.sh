#!/usr/bin/env bash
# Seam 4 — Night Shift two-fire notification contract
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/notify.sh"
SETTINGS="$SCRIPT_DIR/../.claude/settings.shared.json"

WORK="$(mktemp -d /tmp/notify_contract.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0

# --- shim: a fake curl on PATH that logs its argv ------------------------------
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
cap() { OUT="$("$@" 2>"$ERR")"; RC=$?; }

assert_empty() {  # $1 text, $2 msg
  if [ -n "$1" ]; then echo "FAIL: $2 (stdout not empty: $1)"; FAILURES=$((FAILURES + 1)); fi
}
assert_rc0() {  # $1 msg
  if [ "$RC" -ne 0 ]; then echo "FAIL: $1 (expected RC=0, got $RC)"; FAILURES=$((FAILURES + 1)); fi
}
assert_lines() {  # $1 file, $2 expected count, $3 msg
  local n; n=$(wc -l < "$1" | tr -d ' ')
  if [ "$n" -ne "$2" ]; then echo "FAIL: $3 (expected $2 lines, got $n)"; FAILURES=$((FAILURES + 1)); fi
}

# --- Primitive-contract half ---------------------------------------------------
# escalate → fail level → must push exactly once
: > "$CURL_LOG"
cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" fail "Escalation" "task stuck after K"
assert_rc0 "escalate (fail) exits 0"
assert_empty "$OUT" "escalate (fail) stdout pure"
assert_lines "$CURL_LOG" 1 "escalate (fail) pushes exactly once"

# pr-ready → pass level → must push exactly once
: > "$CURL_LOG"
cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" pass "Validate PASS" "branch: PR ready"
assert_rc0 "pr-ready (pass) exits 0"
assert_lines "$CURL_LOG" 1 "pr-ready (pass) pushes exactly once"

# per-step → info level → must NEVER push
: > "$CURL_LOG"
cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" info "Permission needed" "M"
assert_rc0 "per-step (info) exits 0"
assert_lines "$CURL_LOG" 0 "per-step (info) never pushes to the phone"

# --- Config-guard half (Seam 4 regression guard) -------------------------------
# Assert zero Notification hooks remain in the versioned settings file.
matchers="$(python3 - "$SETTINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
notif = d.get("hooks", {}).get("Notification", [])
print(",".join(b.get("matcher","") for b in notif if isinstance(b, dict)))
PY
)"
if [ -n "$matchers" ]; then
  echo "FAIL: per-step Notification hooks must be gone (permission_prompt/idle_prompt); found: $matchers"
  FAILURES=$((FAILURES + 1))
fi

# --- Footer --------------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi

exit $FAILURES
