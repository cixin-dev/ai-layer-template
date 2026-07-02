#!/usr/bin/env bash
# Unit tests for the Night Shift outer loop (scripts/night_shift_loop.sh).
#
# All externals — gh, the executor ($RUN), sleep — are dependency-injected so
# every test runs offline with zero credit spend. Pattern mirrors
# scripts/night_shift_run.test.sh (assert helpers, TIMELINE ordering, fake bins).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOOP="$SCRIPT_DIR/night_shift_loop.sh"

WORK="$(mktemp -d /tmp/nightshiftlooptest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0

assert_eq() {       # $1 got  $2 want  $3 desc
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3 (want '$2' got '$1')"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_contains() {     # $1 haystack  $2 needle  $3 desc
  if ! printf '%s' "$1" | grep -qF -- "$2"; then
    echo "FAIL: $3 (missing '$2')"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_contains() { # $1 haystack  $2 needle  $3 desc
  if printf '%s' "$1" | grep -qF -- "$2"; then
    echo "FAIL: $3 (unexpected '$2')"
    FAILURES=$((FAILURES + 1))
  fi
}

nlines() { wc -l < "$1" | tr -d ' '; }

# =============================================================================
# Fake bins
# =============================================================================

BIN="$WORK/bin"; mkdir -p "$BIN"

# --- fake gh -----------------------------------------------------------------
# FAKE_GH_TSV — the TSV rows gh issue list would emit (tab-separated number<TAB>csv-labels).
# FAKE_CLAIMED — space-separated set of issue numbers that are in-progress.
# All calls are logged to TIMELINE when set.
cat > "$BIN/gh" << 'GHEOF'
#!/usr/bin/env bash
[ -n "${TIMELINE:-}" ] && echo "gh $*" >> "$TIMELINE"
case "$1 $2" in
  "issue list")
    # emit FAKE_GH_TSV lines; add in-progress when pre-claimed or dynamically claimed
    while IFS=$'\t' read -r num labels; do
      [ -z "$num" ] && continue
      extra=""
      # static pre-claim list
      for claimed_n in ${FAKE_CLAIMED:-}; do
        if [ "$claimed_n" = "$num" ]; then extra=",in-progress"; fi
      done
      # dynamic claim written by fake run on failure
      if [ -n "${RUN_STATE:-}" ] && [ -f "${RUN_STATE}/claimed-$num" ]; then
        extra=",in-progress"
      fi
      printf '%s\t%s%s\n' "$num" "$labels" "$extra"
    done <<< "${FAKE_GH_TSV:-}"
    ;;
esac
exit 0
GHEOF
chmod +x "$BIN/gh"

# --- fake RUN (executor) -----------------------------------------------------
# Responds to `snapshot <N>`: emits PR_OPEN and ESCALATED from marker files.
# On `run <N>` (or bare `<N>`): marks the issue terminal and logs to TIMELINE.
# FAKE_RUN_FAIL_N — if set, returns exit 4 for that issue number (failure path).
cat > "$BIN/run" << 'RUNEOF'
#!/usr/bin/env bash
[ -n "${TIMELINE:-}" ] && echo "run $*" >> "$TIMELINE"
cmd="$1"
case "$cmd" in
  snapshot)
    n="$2"
    pr=0; esc=0
    [ -f "${RUN_STATE:-}/pr-open-$n"  ] && pr=1
    [ -f "${RUN_STATE:-}/escalated-$n" ] && esc=1
    printf 'PR_OPEN=%s\nESCALATED=%s\n' "$pr" "$esc"
    ;;
  *)
    # bare number or "run N"
    n="$cmd"
    if [ "${FAKE_RUN_FAIL_NOCLAIM_N:-}" = "$n" ]; then
      # failure WITHOUT claiming: models the claim write not sticking (gh … || true
      # swallowed the error) or the executor dying pre-claim. The Issue stays
      # ready-and-unclaimed, so select_issue keeps returning it (H1 hot-spin bait).
      exit 4
    fi
    if [ "${FAKE_RUN_FAIL_N:-}" = "$n" ]; then
      # failure: write claimed marker (executor kept in-progress); no pr-open
      [ -n "${RUN_STATE:-}" ] && : > "${RUN_STATE}/claimed-$n"
      exit 4
    fi
    # success: mark terminal (pr-open); clear any claimed marker
    if [ -n "${RUN_STATE:-}" ]; then
      : > "${RUN_STATE}/pr-open-$n"
      rm -f "${RUN_STATE}/claimed-$n"
    fi
    ;;
esac
exit 0
RUNEOF
chmod +x "$BIN/run"

# --- fake SLEEP --------------------------------------------------------------
# Logs to TIMELINE. If SLEEP_CREATES_STOP is set, writes the stop file on first
# call (L4: mid-run kill switch test).
cat > "$BIN/fakesleep" << 'SLEEPEOF'
#!/usr/bin/env bash
[ -n "${TIMELINE:-}" ] && echo "sleep $*" >> "$TIMELINE"
if [ "${SLEEP_CREATES_STOP:-0}" = "1" ] && [ ! -f "${STOP_CREATED:-/dev/null}.done" ]; then
  touch "${STOP_FILE_PATH:-}"
  touch "${STOP_CREATED:-/dev/null}.done" 2>/dev/null || true
fi
exit 0
SLEEPEOF
chmod +x "$BIN/fakesleep"

# =============================================================================
# Slice S — select_issue
# =============================================================================

# (S1) lowest-numbered ready Issue wins when multiple are ready.
ST1="$WORK/state-s1"; mkdir -p "$ST1"
RS1="$WORK/run-s1"; mkdir -p "$RS1"
got="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
       RUN_STATE="$RS1" NIGHT_SHIFT_STATE_DIR="$ST1" \
       FAKE_GH_TSV="$(printf '63\tready-for-agent\n62\tready-for-agent')" \
       bash "$LOOP" select 2>&1)"
assert_eq "$got" "62" "(S1) lowest-numbered ready issue wins"

# (S2) in-progress candidates are skipped.
ST2="$WORK/state-s2"; mkdir -p "$ST2"
RS2="$WORK/run-s2"; mkdir -p "$RS2"
# issue 62 is in-progress (via FAKE_CLAIMED), 63 is fresh
got="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
       RUN_STATE="$RS2" NIGHT_SHIFT_STATE_DIR="$ST2" \
       FAKE_GH_TSV="$(printf '62\tready-for-agent\n63\tready-for-agent')" \
       FAKE_CLAIMED="62" \
       bash "$LOOP" select 2>&1)"
assert_eq "$got" "63" "(S2) in-progress issue skipped"

# (S3a) PR_OPEN=1 → issue is terminal, excluded.
ST3a="$WORK/state-s3a"; mkdir -p "$ST3a"
RS3a="$WORK/run-s3a"; mkdir -p "$RS3a"
: > "$RS3a/pr-open-62"   # 62 is terminal (PR open)
got="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
       RUN_STATE="$RS3a" NIGHT_SHIFT_STATE_DIR="$ST3a" \
       FAKE_GH_TSV="$(printf '62\tready-for-agent\n63\tready-for-agent')" \
       bash "$LOOP" select 2>&1)"
assert_eq "$got" "63" "(S3a) PR_OPEN=1 issue excluded; next candidate selected"

# (S3b) ESCALATED=1 → issue is terminal, excluded.
ST3b="$WORK/state-s3b"; mkdir -p "$ST3b"
RS3b="$WORK/run-s3b"; mkdir -p "$RS3b"
: > "$RS3b/escalated-62"   # 62 is escalated
got="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
       RUN_STATE="$RS3b" NIGHT_SHIFT_STATE_DIR="$ST3b" \
       FAKE_GH_TSV="$(printf '62\tready-for-agent\n63\tready-for-agent')" \
       bash "$LOOP" select 2>&1)"
assert_eq "$got" "63" "(S3b) ESCALATED=1 issue excluded; next candidate selected"

# (S4) empty ready set → empty output.
ST4="$WORK/state-s4"; mkdir -p "$ST4"
RS4="$WORK/run-s4"; mkdir -p "$RS4"
got="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
       RUN_STATE="$RS4" NIGHT_SHIFT_STATE_DIR="$ST4" \
       FAKE_GH_TSV="" \
       bash "$LOOP" select 2>&1)"
assert_eq "$got" "" "(S4) empty ready set → empty output"

# =============================================================================
# Slice D — drain
# =============================================================================

# (D1) two ready Issues drained back-to-back; SLEEP never invoked.
TL_D1="$WORK/tl-d1"; : > "$TL_D1"
ST_D1="$WORK/state-d1"; mkdir -p "$ST_D1"
RS_D1="$WORK/run-d1"; mkdir -p "$RS_D1"
RC=0
OUT_D1="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_D1" NIGHT_SHIFT_STATE_DIR="$ST_D1" TIMELINE="$TL_D1" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent\n63\tready-for-agent')" \
           bash "$LOOP" drain 2>&1)" || RC=$?
assert_eq "$RC" "0" "(D1) two-issue drain → exit 0"
assert_contains "$OUT_D1" "dispatch: #62" "(D1) issue 62 dispatched"
assert_contains "$OUT_D1" "dispatch: #63" "(D1) issue 63 dispatched"
assert_not_contains "$(cat "$TL_D1")" "sleep" "(D1) sleep never invoked while work exists"

# (D2) executor failure (rc 4) → drain returns 0, issue stays claimed, no re-dispatch.
# Issue 62 starts fresh (not claimed). Fake run fails with rc 4 and writes a claimed
# marker; fake gh reflects it on the next select call → queue appears empty → drain exits.
TL_D2="$WORK/tl-d2"; : > "$TL_D2"
ST_D2="$WORK/state-d2"; mkdir -p "$ST_D2"
RS_D2="$WORK/run-d2"; mkdir -p "$RS_D2"
RC=0
OUT_D2="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_D2" NIGHT_SHIFT_STATE_DIR="$ST_D2" TIMELINE="$TL_D2" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent')" \
           FAKE_RUN_FAIL_N="62" \
           bash "$LOOP" drain 2>&1)" || RC=$?
assert_eq "$RC" "0" "(D2) executor failure → drain still exits 0"
assert_contains "$OUT_D2" "executor rc=4" "(D2) failure message logged to stderr"
# dispatched exactly once; claimed marker written; no re-dispatch on next pass
dispatch_count="$(grep -c '^run 62$' "$TL_D2" || echo 0)"
assert_eq "$dispatch_count" "1" "(D2) issue dispatched exactly once"
assert_not_contains "$(cat "$TL_D2")" "sleep" "(D2) sleep never invoked in drain"

# (D3) executor fails WITHOUT claiming (claim didn't stick) → drain must NOT hot-spin.
# Issue 62 stays ready-and-unclaimed forever, so a naive drain would re-select and
# re-dispatch it unbounded (the H1 finding). The no-progress guard must end the pass
# after one dispatch. Hard `timeout` turns a regression (infinite loop) into a red
# assertion instead of a hung suite.
TL_D3="$WORK/tl-d3"; : > "$TL_D3"
ST_D3="$WORK/state-d3"; mkdir -p "$ST_D3"
RS_D3="$WORK/run-d3"; mkdir -p "$RS_D3"
RC=0
OUT_D3="$(timeout 20 env NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_D3" NIGHT_SHIFT_STATE_DIR="$ST_D3" TIMELINE="$TL_D3" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent')" \
           FAKE_RUN_FAIL_NOCLAIM_N="62" \
           bash "$LOOP" drain 2>&1)" || RC=$?
assert_eq "$RC" "0" "(D3) claim-not-stuck failure → drain exits 0, no hot-spin (timeout=fail)"
assert_contains "$OUT_D3" "no progress on #62" "(D3) no-progress guard message printed"
dispatch_count_d3="$(grep -c '^run 62$' "$TL_D3" || echo 0)"
assert_eq "$dispatch_count_d3" "1" "(D3) issue dispatched exactly once, not re-dispatched"

# (D4) stuck low Issue must NOT starve a higher ready Issue (#84 head-of-line fix).
# Issue 62 fails-to-claim (stays ready-and-unclaimed → re-selectable forever); 63 is
# ready and succeeds. Skip-and-continue must drain BOTH in one pass: 62 exactly once
# (excluded after its first dispatch → H1 hot-spin bound preserved) and 63 reached —
# a naive drain that ends the pass on 62's no-progress drops 63 (run63 == 0). Hard
# `timeout` turns a head-of-line-blocking regression (loop or drop) into a red
# assertion instead of a hung suite.
TL_D4="$WORK/tl-d4"; : > "$TL_D4"
ST_D4="$WORK/state-d4"; mkdir -p "$ST_D4"
RS_D4="$WORK/run-d4"; mkdir -p "$RS_D4"
RC=0
OUT_D4="$(timeout 20 env NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_D4" NIGHT_SHIFT_STATE_DIR="$ST_D4" TIMELINE="$TL_D4" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent\n63\tready-for-agent')" \
           FAKE_RUN_FAIL_NOCLAIM_N="62" \
           bash "$LOOP" drain 2>&1)" || RC=$?
assert_eq "$RC" "0" "(D4) stuck-low + ready-high → drain exits 0, no hot-spin (timeout=fail)"
assert_contains "$OUT_D4" "dispatch: #62" "(D4) stuck low issue 62 dispatched"
assert_contains "$OUT_D4" "dispatch: #63" "(D4) higher ready issue 63 reached (head-of-line fix)"
run62_d4="$(grep -c '^run 62$' "$TL_D4" || echo 0)"
assert_eq "$run62_d4" "1" "(D4) stuck issue 62 dispatched exactly once (H1 bound preserved)"
run63_d4="$(grep -c '^run 63$' "$TL_D4" || echo 0)"
assert_eq "$run63_d4" "1" "(D4) higher issue 63 dispatched once (would be 0 pre-fix — starved)"

# =============================================================================
# Slice L — loop (persistent poll + kill switch)
# =============================================================================

# (L1) empty queue → loop polls (sleep invoked) then exits after MAX_POLLS.
TL_L1="$WORK/tl-l1"; : > "$TL_L1"
ST_L1="$WORK/state-l1"; mkdir -p "$ST_L1"
RS_L1="$WORK/run-l1"; mkdir -p "$RS_L1"
RC=0
OUT_L1="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_L1" NIGHT_SHIFT_STATE_DIR="$ST_L1" TIMELINE="$TL_L1" \
           FAKE_GH_TSV="" \
           NIGHT_SHIFT_MAX_POLLS=2 \
           bash "$LOOP" loop 2>&1)" || RC=$?
assert_eq "$RC" "0" "(L1) empty queue loop exits 0 after MAX_POLLS"
assert_contains "$OUT_L1" "reached MAX_POLLS=2" "(L1) max polls message"
assert_contains "$(cat "$TL_L1")" "sleep" "(L1) sleep invoked when queue empty"

# (L2) happy-path ordering: dispatch logged BEFORE any sleep.
TL_L2="$WORK/tl-l2"; : > "$TL_L2"
ST_L2="$WORK/state-l2"; mkdir -p "$ST_L2"
RS_L2="$WORK/run-l2"; mkdir -p "$RS_L2"
RC=0
OUT_L2="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_L2" NIGHT_SHIFT_STATE_DIR="$ST_L2" TIMELINE="$TL_L2" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent')" \
           NIGHT_SHIFT_MAX_POLLS=2 \
           bash "$LOOP" loop 2>&1)" || RC=$?
assert_eq "$RC" "0" "(L2) happy-path loop exits 0"
dispatch_ln="$(grep -n 'run 62' "$TL_L2" | head -1 | cut -d: -f1)"
sleep_ln="$(grep -n 'sleep' "$TL_L2" | head -1 | cut -d: -f1 || echo 9999)"
[ "${dispatch_ln:-0}" -lt "${sleep_ln:-9999}" ] && order_ok=yes || order_ok=no
assert_eq "$order_ok" "yes" "(L2) dispatch logged before any sleep (no fixed idle wait)"

# (L3) pre-existing STOP_FILE → exits immediately, no dispatch.
STOP_L3="$WORK/state-l3/stop"
mkdir -p "$WORK/state-l3"
touch "$STOP_L3"
TL_L3="$WORK/tl-l3"; : > "$TL_L3"
RS_L3="$WORK/run-l3"; mkdir -p "$RS_L3"
RC=0
OUT_L3="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           NIGHT_SHIFT_STOP_FILE="$STOP_L3" \
           RUN_STATE="$RS_L3" NIGHT_SHIFT_STATE_DIR="$WORK/state-l3" TIMELINE="$TL_L3" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent')" \
           bash "$LOOP" loop 2>&1)" || RC=$?
assert_eq "$RC" "0" "(L3) pre-existing stop file → exit 0"
assert_contains "$OUT_L3" "kill switch" "(L3) kill switch message printed"
assert_not_contains "$(cat "$TL_L3")" "run 62" "(L3) no dispatch when stop file present"

# (L4) kill switch mid-run: fake sleep writes stop file on first call.
STOP_L4_DIR="$WORK/state-l4"; mkdir -p "$STOP_L4_DIR"
STOP_L4="$STOP_L4_DIR/stop"
TL_L4="$WORK/tl-l4"; : > "$TL_L4"
RS_L4="$WORK/run-l4"; mkdir -p "$RS_L4"
# issue 62 gets drained in first poll; second poll starts, sleep fires, writes stop, loop stops
cat > "$BIN/fakesleep-l4" << SLEEP4EOF
#!/usr/bin/env bash
[ -n "\${TIMELINE:-}" ] && echo "sleep \$*" >> "\$TIMELINE"
touch "$STOP_L4"
exit 0
SLEEP4EOF
chmod +x "$BIN/fakesleep-l4"
RC=0
OUT_L4="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep-l4" \
           NIGHT_SHIFT_STOP_FILE="$STOP_L4" \
           RUN_STATE="$RS_L4" NIGHT_SHIFT_STATE_DIR="$STOP_L4_DIR" TIMELINE="$TL_L4" \
           FAKE_GH_TSV="$(printf '62\tready-for-agent')" \
           NIGHT_SHIFT_MAX_POLLS=5 \
           bash "$LOOP" loop 2>&1)" || RC=$?
assert_eq "$RC" "0" "(L4) mid-run kill switch → exit 0"
assert_contains "$OUT_L4" "kill switch" "(L4) kill switch message after sleep-triggered stop"
# sleep invoked exactly once (second poll stopped by kill switch check)
sleep_count="$(grep -c 'sleep' "$TL_L4" || echo 0)"
assert_eq "$sleep_count" "1" "(L4) sleep invoked exactly once before kill switch detected"

# (L5) CONCURRENCY != 1 → non-zero exit + "serial only" message.
RC=0
OUT_L5="$(NIGHT_SHIFT_CONCURRENCY=2 bash "$LOOP" loop 2>&1)" || RC=$?
[ "$RC" -ne 0 ] && concur_ok=yes || concur_ok=no
assert_eq "$concur_ok" "yes" "(L5) concurrency != 1 exits non-zero"
assert_contains "$OUT_L5" "serial only" "(L5) serial-only error message"

# =============================================================================
# Slice E — entry dispatch (usage vs the credit-spending loop)
# =============================================================================

# (E1) -h/--help print usage and must NOT enter loop(). A regression maps them
# back to loop(); with no MAX_POLLS that loops forever, so `timeout` guards it.
for flag in -h --help; do
  RC=0
  OUT_E="$(timeout 20 bash "$LOOP" "$flag" 2>&1)" || RC=$?
  assert_eq "$RC" "0" "(E1) $flag exits 0"
  assert_contains "$OUT_E" "usage:" "(E1) $flag prints usage"
  assert_not_contains "$OUT_E" "idle: sleeping" "(E1) $flag does not enter loop"
done

# (E2) bare invocation is the documented primary entry → still runs loop().
ST_E2="$WORK/state-e2"; mkdir -p "$ST_E2"
RS_E2="$WORK/run-e2"; mkdir -p "$RS_E2"
RC=0
OUT_E2="$(NIGHT_SHIFT_GH="$BIN/gh" NIGHT_SHIFT_RUN="$BIN/run" \
           NIGHT_SHIFT_SLEEP="$BIN/fakesleep" \
           RUN_STATE="$RS_E2" NIGHT_SHIFT_STATE_DIR="$ST_E2" \
           FAKE_GH_TSV="" NIGHT_SHIFT_MAX_POLLS=1 \
           bash "$LOOP" 2>&1)" || RC=$?
assert_eq "$RC" "0" "(E2) bare invocation exits 0"
assert_contains "$OUT_E2" "reached MAX_POLLS=1" "(E2) bare invocation still enters loop"

# =============================================================================
# Summary
# =============================================================================

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) FAILED."
  exit 1
fi
