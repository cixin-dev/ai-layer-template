#!/usr/bin/env bash
# Unit tests for the thin executor (scripts/night_shift_run.sh).
#
# Every external — claude, gh, git state — is dependency-injected so the
# deterministic seams (snapshot mapping, slug resolution, decision dispatch,
# claim gate, terminal release, MAX_ITERS) run offline with zero credit spend.
# Mirror: scripts/loop_state.test.sh (harness), scripts/notify.test.sh (logging
# fakes), scripts/night_shift_decide.test.sh (decider invocation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN="$SCRIPT_DIR/night_shift_run.sh"

WORK="$(mktemp -d /tmp/nightshiftruntest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0

assert_eq() {  # $1 got  $2 want  $3 desc
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3 (want '$2' got '$1')"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_contains() {  # $1 haystack  $2 needle  $3 desc
  if ! printf '%s' "$1" | grep -qF -- "$2"; then
    echo "FAIL: $3 (missing '$2')"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_contains() {  # $1 haystack  $2 needle  $3 desc
  if printf '%s' "$1" | grep -qF -- "$2"; then
    echo "FAIL: $3 (unexpected '$2')"
    FAILURES=$((FAILURES + 1))
  fi
}

nlines() { wc -l < "$1" | tr -d ' '; }  # line count of a (possibly empty) file

# Extract KEY's value from a `KEY=value` snapshot blob.
field() { printf '%s\n' "$1" | grep -E "^$2=" | cut -d= -f2-; }

# A fresh git repo with one commit (so branches can be created).
mkrepo() {
  local d; d="$(mktemp -d "$WORK/repo.XXXXXX")"
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m init
  printf '%s\n' "$d"
}

# --- fake gh -----------------------------------------------------------------
# Static cases: FAKE_LABELS / FAKE_PR. Stateful drive: when SIM_STATE is set, the
# claim is a `claimed` marker (so `issue view` reflects it dynamically) and the PR
# is a `pr-open` marker (so `pr list` flips once /validate "opens" it). All calls
# are appended to GH_LOG and TIMELINE for ordering assertions.
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" << 'EOF'
#!/usr/bin/env bash
[ -n "${GH_LOG:-}" ]   && echo "gh $*"   >> "$GH_LOG"
[ -n "${TIMELINE:-}" ] && echo "gh $*"   >> "$TIMELINE"
case "$1 $2" in
  "issue view")
    [ -n "${FAKE_LABELS:-}" ] && printf '%s\n' "$FAKE_LABELS"
    if [ -n "${SIM_STATE:-}" ] && [ -f "$SIM_STATE/claimed" ]; then printf 'in-progress\n'; fi
    ;;
  "issue edit")
    if [ -n "${SIM_STATE:-}" ]; then
      case "$*" in
        *"--add-label in-progress"*)    : > "$SIM_STATE/claimed" ;;
        *"--remove-label in-progress"*) rm -f "$SIM_STATE/claimed" ;;
      esac
    fi
    ;;
  "pr list")
    if [ -n "${SIM_STATE:-}" ] && [ -f "$SIM_STATE/pr-open" ]; then
      printf '[{"number":1}]\n'
    else
      printf '%s\n' "${FAKE_PR:-[]}"
    fi
    ;;
esac
exit 0
EOF
chmod +x "$BIN/gh"
export NIGHT_SHIFT_GH="$BIN/gh"

# --- fake claude -------------------------------------------------------------
# Always logs its cwd + the slash command (CLAUDE_LOG and TIMELINE). With
# SIM_MODE=1 it also simulates each phase's durable-artifact effect, so the NEXT
# gather_snapshot advances the decider — proving the executor carries no loop logic.
cat > "$BIN/claude" << 'EOF'
#!/usr/bin/env bash
# claude_run invokes `claude -p "<slash command>"`, so the command is $2.
cmd="$2"
[ -n "${CLAUDE_LOG:-}" ] && echo "claude cwd=$PWD args=$cmd" >> "$CLAUDE_LOG"
[ -n "${TIMELINE:-}" ]   && echo "claude cwd=$PWD args=$cmd" >> "$TIMELINE"
if [ "${SIM_MODE:-0}" = "1" ]; then
  : "${SIM_N:?}" "${SIM_SLUG:?}" "${SIM_ROOT:?}" "${SIM_STATE:?}"
  case "$cmd" in
    *"/plan "*)
      mkdir -p "$SIM_ROOT/.agents/plans"
      printf '| Issue | #%s |\n' "$SIM_N" > "$SIM_ROOT/.agents/plans/$SIM_SLUG.plan.md" ;;
    *"/implement "*)
      mkdir -p "$SIM_ROOT/.agents/reports"
      : > "$SIM_ROOT/.agents/reports/$SIM_SLUG-report.md" ;;
    *"/validate "*)
      # SIM_FAIL_VALIDATE=1 leaves validate as a no-op (never greens) to simulate red gate.
      if [ "${SIM_FAIL_VALIDATE:-0}" != "1" ]; then
        mkdir -p "$SIM_ROOT/.agents/plans/completed"
        mv "$SIM_ROOT/.agents/plans/$SIM_SLUG.plan.md" \
           "$SIM_ROOT/.agents/plans/completed/$SIM_SLUG.plan.md" 2>/dev/null \
           || : > "$SIM_ROOT/.agents/plans/completed/$SIM_SLUG.plan.md"
        : > "$SIM_STATE/pr-open"
      fi ;;
  esac
fi
exit 0
EOF
chmod +x "$BIN/claude"
export NIGHT_SHIFT_CLAUDE="$BIN/claude"

# --- fake notify -------------------------------------------------------------
# Logs "notify level title message" to NOTIFY_LOG when set.
cat > "$BIN/notify" << 'EOF'
#!/usr/bin/env bash
[ -n "${NOTIFY_LOG:-}" ] && printf 'notify %s\n' "$*" >> "$NOTIFY_LOG"
exit 0
EOF
chmod +x "$BIN/notify"

# =============================================================================
# Slice A — resolve-slug
# =============================================================================

# (A1) draft path: a plan file carrying the Issue marker resolves to its slug.
R="$(mktemp -d "$WORK/draft.XXXXXX")"
mkdir -p "$R/.agents/plans"
printf '| Issue | #61 |\n' > "$R/.agents/plans/the-feature.plan.md"
got="$(NIGHT_SHIFT_ROOT="$R" bash "$RUN" resolve-slug 61)"
assert_eq "$got" "the-feature" "(A1) resolve-slug from draft marker"

# (A2) branch path is authoritative post-implement (no draft present).
R="$(mkrepo)"
git -C "$R" branch feat/61-shipped
got="$(NIGHT_SHIFT_ROOT="$R" bash "$RUN" resolve-slug 61)"
assert_eq "$got" "shipped" "(A2) resolve-slug from branch (authoritative)"

# (A3) nothing present → empty slug.
R="$(mktemp -d "$WORK/empty.XXXXXX")"
got="$(NIGHT_SHIFT_ROOT="$R" bash "$RUN" resolve-slug 61)"
assert_eq "$got" "" "(A3) resolve-slug none → empty"

# =============================================================================
# Slice A — snapshot (artifact → decider env mapping)
# =============================================================================

# (A4) pre-plan: ready Issue, no artifacts.
R="$(mktemp -d "$WORK/preplan.XXXXXX")"
snap="$(NIGHT_SHIFT_ROOT="$R" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" ISSUE_READY)"    "1"     "(A4) ready label → ISSUE_READY=1"
assert_eq "$(field "$snap" PLAN_PRESENT)"   "0"     "(A4) no plan → PLAN_PRESENT=0"
assert_eq "$(field "$snap" REPORT_PRESENT)" "0"     "(A4) no report → REPORT_PRESENT=0"
assert_eq "$(field "$snap" GATE)"           "unrun" "(A4) no completed → GATE=unrun"
assert_eq "$(field "$snap" PR_OPEN)"        "0"     "(A4) no PR → PR_OPEN=0"
assert_eq "$(field "$snap" ESCALATED)"      "0"     "(A4) no escalation marker → ESCALATED=0"

# (A5) post-plan draft: plan present, no report.
R="$(mktemp -d "$WORK/postplan.XXXXXX")"
mkdir -p "$R/.agents/plans"
printf '| Issue | #61 |\n' > "$R/.agents/plans/the-feature.plan.md"
snap="$(NIGHT_SHIFT_ROOT="$R" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" PLAN_PRESENT)"   "1"     "(A5) draft plan → PLAN_PRESENT=1"
assert_eq "$(field "$snap" REPORT_PRESENT)" "0"     "(A5) no report yet → REPORT_PRESENT=0"
assert_eq "$(field "$snap" GATE)"           "unrun" "(A5) draft not completed → GATE=unrun"

# (A6) FAITHFULNESS: report present + plan NOT in completed/ ⇒ GATE=unrun.
# piv_check.sh goes green once plan+report exist (before /validate archives), so the
# executor must NOT derive GATE from that — only completed/ presence means validate passed.
R="$(mkrepo)"
git -C "$R" branch feat/61-the-feature
mkdir -p "$R/.agents/plans" "$R/.agents/reports"
printf '| Issue | #61 |\n' > "$R/.agents/plans/the-feature.plan.md"
: > "$R/.agents/reports/the-feature-report.md"
snap="$(NIGHT_SHIFT_ROOT="$R" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" REPORT_PRESENT)" "1"     "(A6) report present → REPORT_PRESENT=1"
assert_eq "$(field "$snap" GATE)"           "unrun" "(A6) report present but not archived → GATE=unrun"

# (A7) FAITHFULNESS: plan archived to completed/ ⇒ GATE=green.
R="$(mkrepo)"
git -C "$R" branch feat/61-the-feature
mkdir -p "$R/.agents/plans/completed" "$R/.agents/reports"
: > "$R/.agents/plans/completed/the-feature.plan.md"
: > "$R/.agents/reports/the-feature-report.md"
snap="$(NIGHT_SHIFT_ROOT="$R" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" PLAN_PRESENT)"   "1"      "(A7) completed plan still counts as present"
assert_eq "$(field "$snap" GATE)"           "green"  "(A7) completed/ present → GATE=green"

# (A8) PR open → PR_OPEN=1.
R="$(mkrepo)"
git -C "$R" branch feat/61-the-feature
snap="$(NIGHT_SHIFT_ROOT="$R" FAKE_LABELS="ready-for-agent" FAKE_PR='[{"number":7}]' bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" PR_OPEN)"        "1"      "(A8) non-empty pr list → PR_OPEN=1"

# (A9) worktree root switch: artifacts in the worktree (not ROOT) are still seen.
R="$(mkrepo)"
git -C "$R" branch feat/61-the-feature
WT="$WORK/wt-the-feature"
git -C "$R" worktree add -q "$WT" feat/61-the-feature
mkdir -p "$WT/.agents/reports"
: > "$WT/.agents/reports/the-feature-report.md"
snap="$(NIGHT_SHIFT_ROOT="$R" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" REPORT_PRESENT)" "1"      "(A9) report read from worktree, not ROOT"

# (A-red) phase=validate + report present + no completed/ + no escalation → GATE=red.
R="$(mkrepo)"; git -C "$R" branch feat/61-red-feature
WT_RED="$WORK/wt-red"; git -C "$R" worktree add -q "$WT_RED" feat/61-red-feature
mkdir -p "$WT_RED/.agents/plans" "$WT_RED/.agents/reports"
printf '| Issue | #61 |\n' > "$WT_RED/.agents/plans/red-feature.plan.md"
: > "$WT_RED/.agents/reports/red-feature-report.md"
ST_RED="$WORK/state-red"
NIGHT_SHIFT_STATE_DIR="$ST_RED" bash "$SCRIPT_DIR/loop_state.sh" set-phase 61 validate
snap="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$ST_RED" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" GATE)"      "red" "(A-red) phase=validate + report + no completed → GATE=red"
assert_eq "$(field "$snap" ESCALATED)" "0"   "(A-red) no escalation marker → ESCALATED=0"

# (A-green-prec) completed/ present + phase=validate → GATE=green (green takes precedence).
R2="$(mkrepo)"; git -C "$R2" branch feat/61-red-feature
WT_GP="$WORK/wt-gp"; git -C "$R2" worktree add -q "$WT_GP" feat/61-red-feature
mkdir -p "$WT_GP/.agents/plans/completed" "$WT_GP/.agents/reports"
: > "$WT_GP/.agents/plans/completed/red-feature.plan.md"
: > "$WT_GP/.agents/reports/red-feature-report.md"
ST_GP="$WORK/state-gp"
NIGHT_SHIFT_STATE_DIR="$ST_GP" bash "$SCRIPT_DIR/loop_state.sh" set-phase 61 validate
snap="$(NIGHT_SHIFT_ROOT="$R2" NIGHT_SHIFT_STATE_DIR="$ST_GP" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" GATE)" "green" "(A-green-prec) completed/ present overrides phase=validate → GATE=green"

# (A-esc) escalated + phase=validate + report → GATE not red (unrun); ESCALATED=1.
R3="$(mkrepo)"; git -C "$R3" branch feat/61-red-feature
WT_ESC="$WORK/wt-esc"; git -C "$R3" worktree add -q "$WT_ESC" feat/61-red-feature
mkdir -p "$WT_ESC/.agents/plans" "$WT_ESC/.agents/reports"
printf '| Issue | #61 |\n' > "$WT_ESC/.agents/plans/red-feature.plan.md"
: > "$WT_ESC/.agents/reports/red-feature-report.md"
ST_ESC="$WORK/state-esc"
NIGHT_SHIFT_STATE_DIR="$ST_ESC" bash "$SCRIPT_DIR/loop_state.sh" set-phase 61 validate
NIGHT_SHIFT_STATE_DIR="$ST_ESC" bash "$SCRIPT_DIR/loop_state.sh" set-escalated 61
snap="$(NIGHT_SHIFT_ROOT="$R3" NIGHT_SHIFT_STATE_DIR="$ST_ESC" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" GATE)"      "unrun" "(A-esc) escalated suppresses red → GATE=unrun"
assert_eq "$(field "$snap" ESCALATED)" "1"     "(A-esc) set-escalated → ESCALATED=1 in snapshot"

# (A-attempts) incr-attempts × 2 → snapshot emits ATTEMPTS=2.
R4="$(mkrepo)"; git -C "$R4" branch feat/61-the-feature
ST_ATT="$WORK/state-att"
NIGHT_SHIFT_STATE_DIR="$ST_ATT" bash "$SCRIPT_DIR/loop_state.sh" incr-attempts 61 >/dev/null
NIGHT_SHIFT_STATE_DIR="$ST_ATT" bash "$SCRIPT_DIR/loop_state.sh" incr-attempts 61 >/dev/null
snap="$(NIGHT_SHIFT_ROOT="$R4" NIGHT_SHIFT_STATE_DIR="$ST_ATT" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" ATTEMPTS)" "2" "(A-attempts) two incr-attempts → ATTEMPTS=2 in snapshot"

# (A-noesc) fresh task → ESCALATED=0 and ATTEMPTS=0 in snapshot.
R5="$(mkrepo)"; git -C "$R5" branch feat/61-the-feature
ST_NOESC="$WORK/state-noesc"
snap="$(NIGHT_SHIFT_ROOT="$R5" NIGHT_SHIFT_STATE_DIR="$ST_NOESC" FAKE_LABELS="ready-for-agent" bash "$RUN" snapshot 61)"
assert_eq "$(field "$snap" ESCALATED)" "0" "(A-noesc) fresh task → ESCALATED=0"
assert_eq "$(field "$snap" ATTEMPTS)"  "0" "(A-noesc) fresh task → ATTEMPTS=0"

# =============================================================================
# Slice B — dispatch (one decision → the correct command in the correct cwd)
# =============================================================================

# (B1) run-plan → /plan in the clone root; phase recorded.
R="$(mktemp -d "$WORK/disp-plan.XXXXXX")"
ST="$WORK/state-b1"; CLOG="$WORK/clog-b1"; : > "$CLOG"
NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$ST" CLAUDE_LOG="$CLOG" \
  bash "$RUN" dispatch run-plan 61
log="$(cat "$CLOG")"
assert_contains "$log" "args=/plan 61" "(B1) run-plan invokes /plan 61"
assert_contains "$log" "cwd=$R"        "(B1) run-plan runs in the clone root"
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$ST" bash "$SCRIPT_DIR/loop_state.sh" get-phase 61)" \
          "plan" "(B1) run-plan records phase=plan"

# (B2) run-implement → /implement with the ROOT draft path; phase recorded.
R="$(mktemp -d "$WORK/disp-impl.XXXXXX")"
mkdir -p "$R/.agents/plans"
printf '| Issue | #61 |\n' > "$R/.agents/plans/foo.plan.md"
ST="$WORK/state-b2"; CLOG="$WORK/clog-b2"; : > "$CLOG"
NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$ST" CLAUDE_LOG="$CLOG" \
  bash "$RUN" dispatch run-implement 61
log="$(cat "$CLOG")"
assert_contains "$log" "args=/implement $R/.agents/plans/foo.plan.md" "(B2) run-implement passes the ROOT draft path"
assert_contains "$log" "cwd=$R" "(B2) run-implement runs in the clone root"
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$ST" bash "$SCRIPT_DIR/loop_state.sh" get-phase 61)" \
          "implement" "(B2) run-implement records phase=implement"

# (B3) run-validate → /validate in the WORKTREE with the worktree plan path.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
WT="$WORK/wt-b3"; git -C "$R" worktree add -q "$WT" feat/61-foo
mkdir -p "$WT/.agents/plans"; : > "$WT/.agents/plans/foo.plan.md"
ST="$WORK/state-b3"; CLOG="$WORK/clog-b3"; GLOG="$WORK/glog-b3"; : > "$CLOG"; : > "$GLOG"
NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$ST" CLAUDE_LOG="$CLOG" GH_LOG="$GLOG" \
  bash "$RUN" dispatch run-validate 61
log="$(cat "$CLOG")"
assert_contains "$log" "args=/validate $WT/.agents/plans/foo.plan.md" "(B3) run-validate passes the worktree plan path"
assert_contains "$log" "cwd=$WT" "(B3) run-validate runs in the feature worktree"
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$ST" bash "$SCRIPT_DIR/loop_state.sh" get-phase 61)" \
          "validate" "(B3) run-validate records phase=validate"
# (B5) the executor delegates push/PR/notify to /validate — it calls no gh itself.
assert_eq "$(nlines "$GLOG")" "0" "(B5) dispatch performs no gh of its own (no push/PR/notify)"
assert_not_contains "$log" "push"      "(B5) dispatch issues no git push"
assert_not_contains "$log" "pr create" "(B5) dispatch opens no PR"

# (B4) open-pr (idempotent fallback) → re-invoke /validate on the archived plan.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
WT="$WORK/wt-b4"; git -C "$R" worktree add -q "$WT" feat/61-foo
mkdir -p "$WT/.agents/plans/completed"; : > "$WT/.agents/plans/completed/foo.plan.md"
CLOG="$WORK/clog-b4"; : > "$CLOG"
NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$WORK/state-b4" CLAUDE_LOG="$CLOG" \
  bash "$RUN" dispatch open-pr 61
log="$(cat "$CLOG")"
assert_contains "$log" "args=/validate $WT/.agents/plans/completed/foo.plan.md" "(B4) open-pr re-invokes /validate on the archived plan"
assert_contains "$log" "cwd=$WT" "(B4) open-pr runs in the feature worktree"

# (B-reimpl) retry-reimplement → /implement <wt>/<plan> in cwd=worktree; phase=implement.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
WT_RI="$WORK/wt-b-reimpl"; git -C "$R" worktree add -q "$WT_RI" feat/61-foo
mkdir -p "$WT_RI/.agents/plans"; : > "$WT_RI/.agents/plans/foo.plan.md"
ST_RI="$WORK/state-b-reimpl"; CLOG_RI="$WORK/clog-b-reimpl"; : > "$CLOG_RI"
NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$ST_RI" CLAUDE_LOG="$CLOG_RI" \
  bash "$RUN" dispatch retry-reimplement 61
log_ri="$(cat "$CLOG_RI")"
assert_contains "$log_ri" "args=/implement $WT_RI/.agents/plans/foo.plan.md" "(B-reimpl) retry-reimplement passes the worktree plan path"
assert_contains "$log_ri" "cwd=$WT_RI"                                        "(B-reimpl) retry-reimplement runs in the worktree"
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$ST_RI" bash "$SCRIPT_DIR/loop_state.sh" get-phase 61)" \
          "implement" "(B-reimpl) retry-reimplement records phase=implement"

# (B-replan) retry-replan → /plan 61 in cwd=worktree; phase=plan.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
WT_RP="$WORK/wt-b-replan"; git -C "$R" worktree add -q "$WT_RP" feat/61-foo
ST_RP="$WORK/state-b-replan"; CLOG_RP="$WORK/clog-b-replan"; : > "$CLOG_RP"
NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$ST_RP" CLAUDE_LOG="$CLOG_RP" \
  bash "$RUN" dispatch retry-replan 61
log_rp="$(cat "$CLOG_RP")"
assert_contains "$log_rp" "args=/plan 61"  "(B-replan) retry-replan invokes /plan 61"
assert_contains "$log_rp" "cwd=$WT_RP"    "(B-replan) retry-replan runs in the worktree"
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$ST_RP" bash "$SCRIPT_DIR/loop_state.sh" get-phase 61)" \
          "plan" "(B-replan) retry-replan records phase=plan"

# (B-escalate) escalate → notify(fail, phase+attempts), set-escalated; no claude, no pr.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
WT_ESC2="$WORK/wt-b-esc"; git -C "$R" worktree add -q "$WT_ESC2" feat/61-foo
ST_ESC2="$WORK/state-b-esc"
NIGHT_SHIFT_STATE_DIR="$ST_ESC2" bash "$SCRIPT_DIR/loop_state.sh" set-phase 61 validate
NIGHT_SHIFT_STATE_DIR="$ST_ESC2" bash "$SCRIPT_DIR/loop_state.sh" incr-attempts 61 >/dev/null
NIGHT_SHIFT_STATE_DIR="$ST_ESC2" bash "$SCRIPT_DIR/loop_state.sh" incr-attempts 61 >/dev/null
NIGHT_SHIFT_STATE_DIR="$ST_ESC2" bash "$SCRIPT_DIR/loop_state.sh" incr-attempts 61 >/dev/null
CLOG_ESC2="$WORK/clog-b-esc"; GLOG_ESC2="$WORK/glog-b-esc"; NLOG_ESC2="$WORK/nlog-b-esc"
: > "$CLOG_ESC2"; : > "$GLOG_ESC2"; : > "$NLOG_ESC2"
NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$ST_ESC2" \
  CLAUDE_LOG="$CLOG_ESC2" GH_LOG="$GLOG_ESC2" \
  NOTIFY_LOG="$NLOG_ESC2" NIGHT_SHIFT_NOTIFY="$BIN/notify" \
  bash "$RUN" dispatch escalate 61
nlog_esc2="$(cat "$NLOG_ESC2")"
assert_contains "$nlog_esc2"  "fail"     "(B-escalate) notify called with level=fail"
assert_contains "$nlog_esc2"  "validate" "(B-escalate) notify message contains phase"
assert_contains "$nlog_esc2"  "3"        "(B-escalate) notify message contains attempt count"
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$ST_ESC2" bash "$SCRIPT_DIR/loop_state.sh" get-escalated 61)" \
          "1" "(B-escalate) set-escalated marker written"
assert_eq "$(cat "$CLOG_ESC2")" "" "(B-escalate) no claude invocation on escalate"
assert_not_contains "$(cat "$GLOG_ESC2")" "pr create" "(B-escalate) no gh pr create on escalate"

# =============================================================================
# Slice C — drive loop + claim gate + selection
# =============================================================================

# (C1) skip an already-claimed Issue (never double-grab) — no claim, no dispatch.
R="$(mktemp -d "$WORK/c1.XXXXXX")"
ST="$WORK/sim-c1"; mkdir -p "$ST"; : > "$ST/claimed"   # already in-progress
TL="$WORK/tl-c1"; : > "$TL"
RC=0
OUT="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$WORK/state-c1" \
        FAKE_LABELS="ready-for-agent" SIM_STATE="$ST" TIMELINE="$TL" \
        bash "$RUN" run 61 2>&1)" || RC=$?
assert_eq "$RC" "0" "(C1) already-claimed → exit 0"
assert_contains "$OUT" "skip: already claimed" "(C1) prints already-claimed skip"
assert_not_contains "$(cat "$TL")" "claude"     "(C1) no phase dispatched"
assert_not_contains "$(cat "$TL")" "issue edit" "(C1) no re-claim attempted"

# (C2) skip an Issue without the trigger label.
R="$(mktemp -d "$WORK/c2.XXXXXX")"
TL="$WORK/tl-c2"; : > "$TL"
RC=0
OUT="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$WORK/state-c2" \
        FAKE_LABELS="" TIMELINE="$TL" \
        bash "$RUN" run 61 2>&1)" || RC=$?
assert_eq "$RC" "0" "(C2) not-ready → exit 0"
assert_contains "$OUT" "skip: not ready" "(C2) prints not-ready skip"
assert_not_contains "$(cat "$TL")" "claude" "(C2) no phase dispatched"

# (C3) full happy-path drive: every action comes from the decider, end to end.
# ROOT is a git repo with feat/61-foo pre-created (the state /implement would
# leave) so resolve_slug is stable without spinning a real worktree — the live
# Task 6 probe covers real worktrees end to end. SIM_MODE makes each fake phase
# write its durable artifact, advancing the snapshot for the next iteration.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
ST="$WORK/sim-c3"; mkdir -p "$ST"
TL="$WORK/tl-c3"; : > "$TL"
STATE_C3="$WORK/state-c3"
RC=0
OUT="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$STATE_C3" \
        FAKE_LABELS="ready-for-agent" SIM_STATE="$ST" TIMELINE="$TL" \
        SIM_MODE=1 SIM_N=61 SIM_SLUG=foo SIM_ROOT="$R" \
        bash "$RUN" run 61 2>&1)" || RC=$?
tl="$(cat "$TL")"
assert_eq "$RC" "0" "(C3) happy-path drive → exit 0"
assert_contains "$OUT" "done: #61" "(C3) reaches terminal done"
# exactly three phase sessions, in PIV order
assert_eq "$(printf '%s\n' "$tl" | grep -c 'claude .*args=/')" "3" "(C3) exactly 3 fresh phase sessions"
plan_ln="$(printf '%s\n' "$tl" | grep -n 'args=/plan '      | head -1 | cut -d: -f1)"
impl_ln="$(printf '%s\n' "$tl" | grep -n 'args=/implement ' | head -1 | cut -d: -f1)"
val_ln="$(printf '%s\n' "$tl" | grep -n 'args=/validate '   | head -1 | cut -d: -f1)"
[ "$plan_ln" -lt "$impl_ln" ] && [ "$impl_ln" -lt "$val_ln" ] \
  && ord_ok=yes || ord_ok=no
assert_eq "$ord_ok" "yes" "(C3) phases ran in plan→implement→validate order"
# claim BEFORE any worktree-creating dispatch (claim-before-worktree)
claim_ln="$(printf '%s\n' "$tl" | grep -n 'issue edit 61 --add-label in-progress' | head -1 | cut -d: -f1)"
first_dispatch_ln="$(printf '%s\n' "$tl" | grep -n 'claude .*args=/' | head -1 | cut -d: -f1)"
[ "$claim_ln" -lt "$first_dispatch_ln" ] && claim_ok=yes || claim_ok=no
assert_eq "$claim_ok" "yes" "(C3) in-progress claimed before any dispatch"
# release on terminal; executor never opens a PR itself
assert_contains "$tl" "issue edit 61 --remove-label in-progress" "(C3) claim released on terminal"
assert_not_contains "$tl" "pr create" "(C3) executor never opens the PR (delegated to /validate)"
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$STATE_C3" bash "$SCRIPT_DIR/loop_state.sh" get-phase 61)" \
          "validate" "(C3) last recorded phase is validate"

# (C4) terminal no-op: a PR already open → decider says noop → release, no dispatch.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
ST="$WORK/sim-c4"; mkdir -p "$ST"; : > "$ST/pr-open"   # PR already exists
TL="$WORK/tl-c4"; : > "$TL"
RC=0
OUT="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$WORK/state-c4" \
        FAKE_LABELS="ready-for-agent" SIM_STATE="$ST" TIMELINE="$TL" \
        bash "$RUN" run 61 2>&1)" || RC=$?
assert_eq "$RC" "0" "(C4) terminal no-op → exit 0"
assert_contains "$OUT" "done: #61" "(C4) reaches done"
assert_not_contains "$(cat "$TL")" "claude" "(C4) no phase dispatched when PR already open"
assert_contains "$(cat "$TL")" "issue edit 61 --remove-label in-progress" "(C4) claim released"

# (C5) MAX_ITERS safety stop: a non-advancing phase never reaches noop → exit 3.
R="$(mktemp -d "$WORK/c5.XXXXXX")"   # plain dir, no artifacts ever appear
TL="$WORK/tl-c5"; : > "$TL"
RC=0
OUT="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$WORK/state-c5" \
        FAKE_LABELS="ready-for-agent" TIMELINE="$TL" NIGHT_SHIFT_MAX_ITERS=3 \
        bash "$RUN" run 61 2>&1)" || RC=$?
assert_eq "$RC" "3" "(C5) runaway hits MAX_ITERS → exit 3"
assert_eq "$(printf '%s\n' "$(cat "$TL")" | grep -c 'claude .*args=/plan')" "3" "(C5) stopped after exactly MAX_ITERS iterations"

# (C-fail) full failure-path drive: red gate → retry ladder → escalation → terminal no-op.
# Validate never greens (SIM_FAIL_VALIDATE=1): plan+impl+val → red×1 (reimpl) →
# val → red×2 (replan) → impl+val → red×3 (escalate) → noop. Second run is pure noop.
R="$(mkrepo)"; git -C "$R" branch feat/61-foo
ST_CF="$WORK/sim-c-fail"; mkdir -p "$ST_CF"
STATE_CF="$WORK/state-c-fail"
TL_CF="$WORK/tl-c-fail"; NLOG_CF="$WORK/nlog-c-fail"; : > "$TL_CF"; : > "$NLOG_CF"
RC=0
OUT_CF="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$STATE_CF" \
            FAKE_LABELS="ready-for-agent" SIM_STATE="$ST_CF" TIMELINE="$TL_CF" \
            SIM_MODE=1 SIM_FAIL_VALIDATE=1 SIM_N=61 SIM_SLUG=foo SIM_ROOT="$R" \
            NOTIFY_LOG="$NLOG_CF" NIGHT_SHIFT_NOTIFY="$BIN/notify" \
            NIGHT_SHIFT_MAX_ATTEMPTS=3 \
            bash "$RUN" run 61 2>&1)" || RC=$?
tl_cf="$(cat "$TL_CF")"
nlog_cf="$(cat "$NLOG_CF")"
assert_eq "$RC" "0" "(C-fail) failure drive → exit 0"
assert_contains "$OUT_CF" "done: #61" "(C-fail) reaches terminal done"
# exactly one escalation notify
assert_eq "$(printf '%s\n' "$nlog_cf" | grep -c 'notify')" "1" "(C-fail) exactly one notify call"
assert_contains "$nlog_cf" "fail"     "(C-fail) notify level=fail"
assert_contains "$nlog_cf" "validate" "(C-fail) notify message contains phase"
assert_contains "$nlog_cf" "3"        "(C-fail) notify message contains attempt count (3)"
# escalated marker persists across the run
assert_eq "$(NIGHT_SHIFT_STATE_DIR="$STATE_CF" bash "$SCRIPT_DIR/loop_state.sh" get-escalated 61)" \
          "1" "(C-fail) escalated=1 persists after run"
# retry order: retry-reimplement (/implement) fires before retry-replan (/plan)
first_val_ln="$(awk '/args=\/validate /{print NR; exit}' "$TL_CF")"
first_retry_cmd="$(awk -v n="$first_val_ln" 'NR>n && /args=\//{ print; exit }' "$TL_CF")"
assert_contains "$first_retry_cmd" "/implement" "(C-fail) first retry after red gate is /implement (retry-reimplement)"
replan_line="$(awk -v n="$first_val_ln" 'NR>n && /args=\/plan /{ print; exit }' "$TL_CF")"
assert_contains "$replan_line" "/plan" "(C-fail) retry-replan (/plan) fires during ladder"
# second run is a pure no-op: claim → noop (ESCALATED=1) → release; no new notify
OUT_CF2="$(NIGHT_SHIFT_ROOT="$R" NIGHT_SHIFT_STATE_DIR="$STATE_CF" \
              FAKE_LABELS="ready-for-agent" SIM_STATE="$ST_CF" \
              NOTIFY_LOG="$NLOG_CF" NIGHT_SHIFT_NOTIFY="$BIN/notify" \
              bash "$RUN" run 61 2>&1)"
assert_contains "$OUT_CF2" "done: #61" "(C-fail) second run → done (noop)"
assert_eq "$(cat "$NLOG_CF" | grep -c 'notify')" "1" "(C-fail) no second notify on re-run"

# --- summary -----------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
