#!/usr/bin/env bash
# night_shift_run.sh — the Night Shift thin executor.
#
# Drives one `ready` Issue through Plan → Implement → Validate with no human
# between phases. It carries NO loop logic: every "what next" comes from the pure
# decider (scripts/night_shift_decide.sh, ADR-0023). This script only knows HOW
# to perform each action — never WHETHER. Each phase runs in a fresh, isolated
# session: a separate `claude -p "/<phase>"` subprocess (ADR-0024).
#
# Substrate (ADR-0024): phase sessions run on the operator's claude.ai
# subscription (~/.claude/.credentials.json); the host must NOT export an
# ANTHROPIC_API_KEY (it would take precedence over the login). The executor runs
# in a dedicated Night Shift clone, resolving the HEAD race (CLAUDE.md).
#
# Usage:
#   night_shift_run.sh <issue-number>          # drive the Issue (claim → loop)
#   night_shift_run.sh snapshot <N>            # print the decider env snapshot
#   night_shift_run.sh resolve-slug <N>        # print the resolved plan slug
#   night_shift_run.sh dispatch <decision> <N> # perform one decision's action
#
# Externals are dependency-injected (so the seams test offline):
#   NIGHT_SHIFT_CLAUDE  (default: claude)   phase-session spawner
#   NIGHT_SHIFT_GH      (default: gh)       Issue labels / PR state / claim
#   NIGHT_SHIFT_ROOT    (default: repo root) the clone's main checkout
#   NIGHT_SHIFT_STATE_DIR (default: $ROOT/.night-shift)  loop_state store
#   NIGHT_SHIFT_TRIGGER_LABEL (default: ready-for-agent) pickup trigger (#63 renames)
#   NIGHT_SHIFT_CLAIM_LABEL   (default: in-progress)     claim label
#   NIGHT_SHIFT_MAX_ITERS     (default: 6)               runaway safety cap
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CLAUDE="${NIGHT_SHIFT_CLAUDE:-claude}"
GH="${NIGHT_SHIFT_GH:-gh}"
ROOT="${NIGHT_SHIFT_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}"
TRIGGER_LABEL="${NIGHT_SHIFT_TRIGGER_LABEL:-ready-for-agent}"
CLAIM_LABEL="${NIGHT_SHIFT_CLAIM_LABEL:-in-progress}"
MAX_ATTEMPTS_K="${NIGHT_SHIFT_MAX_ATTEMPTS:-3}"  # mirrors decider default K; executor is source of truth
# Worst-case ladder: plan+impl+val + (reimpl+val)×K-2 + (replan+impl+val) + noop = 3*K+6
MAX_ITERS="${NIGHT_SHIFT_MAX_ITERS:-$(( 3 * MAX_ATTEMPTS_K + 6 ))}"
DECIDER="$SCRIPT_DIR/night_shift_decide.sh"
STORE="$SCRIPT_DIR/loop_state.sh"

# State store shared with loop_state.sh; pin it to the clone root so every phase
# writes to one place regardless of the dispatch cwd.
export NIGHT_SHIFT_STATE_DIR="${NIGHT_SHIFT_STATE_DIR:-$ROOT/.night-shift}"

# --- gh helpers --------------------------------------------------------------
_labels() {  # N → newline-separated label names
  "$GH" issue view "$1" --json labels --jq '.labels[].name' 2>/dev/null || true
}
_has_label() {  # N label → exit 0 if present
  _labels "$1" | grep -Fxq -- "$2"
}
_pr_open() {  # branch → exit 0 if an open PR exists for the branch
  local out
  out="$("$GH" pr list --head "$1" --state open --json number 2>/dev/null || true)"
  [ -n "$out" ] && [ "$out" != "[]" ]
}

# --- slug / branch / worktree resolution -------------------------------------
# Branch is authoritative once /implement has run; the draft marker covers the
# narrow post-plan/pre-implement window before a branch exists.
resolve_slug() {  # N → slug ("" if unresolved)
  local n="$1" b f
  # `|| true`: a non-git ROOT makes `git` exit 128, which pipefail would
  # propagate and set -e would treat as fatal. An unresolved slug is not an error.
  b="$(git -C "$ROOT" branch --list "feat/${n}-*" 2>/dev/null | head -1 | sed 's/^[*+ ]*//' || true)"
  if [ -n "$b" ]; then
    printf '%s\n' "${b#feat/${n}-}"
    return 0
  fi
  for f in "$ROOT"/.agents/plans/*.plan.md; do
    [ -e "$f" ] || continue
    if grep -qE "^\| Issue \| #${n} \|" "$f"; then
      basename "$f" .plan.md
      return 0
    fi
  done
  printf '\n'
}

worktree_path() {  # branch → path ("" if no worktree checked out at it)
  git -C "$ROOT" worktree list --porcelain 2>/dev/null \
    | bash "$SCRIPT_DIR/worktree_path.sh" "$1" || true
}

# Where this task's durable artifacts live: the worktree once it exists, else ROOT.
_artifact_root() {  # branch → dir
  local wt=""
  [ -n "$1" ] && wt="$(worktree_path "$1")"
  if [ -n "$wt" ]; then printf '%s\n' "$wt"; else printf '%s\n' "$ROOT"; fi
}

# --- snapshot: durable artifact state → the decider's env vars ----------------
gather_snapshot() {  # N → KEY=value lines
  local n="$1" slug branch root
  slug="$(resolve_slug "$n")"
  branch=""; [ -n "$slug" ] && branch="feat/${n}-${slug}"
  root="$(_artifact_root "$branch")"

  local issue_ready=0 plan_present=0 report_present=0 gate=unrun pr_open=0
  local phase escalated attempts
  phase="$(bash "$STORE" get-phase "$n")"
  escalated="$(bash "$STORE" get-escalated "$n")"
  attempts="$(bash "$STORE" get-attempts "$n")"

  _has_label "$n" "$TRIGGER_LABEL" && issue_ready=1
  if [ -n "$slug" ]; then
    if [ -f "$root/.agents/plans/${slug}.plan.md" ] \
       || [ -f "$root/.agents/plans/completed/${slug}.plan.md" ]; then
      plan_present=1
    fi
    [ -f "$root/.agents/reports/${slug}-report.md" ] && report_present=1
    if [ -f "$root/.agents/plans/completed/${slug}.plan.md" ]; then
      gate=green
    elif [ "$phase" = "validate" ] && [ "$report_present" = "1" ] && [ "$escalated" != "1" ]; then
      gate=red
    fi
  fi
  [ -n "$branch" ] && _pr_open "$branch" && pr_open=1

  printf 'ISSUE_READY=%s\n'    "$issue_ready"
  printf 'PLAN_PRESENT=%s\n'   "$plan_present"
  printf 'REPORT_PRESENT=%s\n' "$report_present"
  printf 'GATE=%s\n'           "$gate"
  printf 'PR_OPEN=%s\n'        "$pr_open"
  printf 'ESCALATED=%s\n'      "$escalated"
  printf 'ATTEMPTS=%s\n'       "$attempts"
}

# --- dispatch: perform exactly the action the decider chose ------------------
# Blocking. The return of each phase IS the phase-complete event. Each phase runs
# in a fresh `claude -p` session (stdin /dev/null avoids the interactive wait).
# The executor adds NO push/PR/notify of its own — /validate Phase 5 owns those.
claude_run() {  # dir cmd
  ( cd "$1" && "$CLAUDE" -p "$2" < /dev/null )
}

# The plan path inside a checkout, preferring the archived copy once it exists
# (so open-pr's re-validate hands /validate the completed/ path, not a stale one).
_plan_path_in() {  # dir slug
  if [ -f "$1/.agents/plans/completed/${2}.plan.md" ]; then
    printf '%s\n' "$1/.agents/plans/completed/${2}.plan.md"
  else
    printf '%s\n' "$1/.agents/plans/${2}.plan.md"
  fi
}

dispatch() {  # decision N
  local decision="$1" n="$2" slug branch dir pp
  slug="$(resolve_slug "$n")"
  branch=""; [ -n "$slug" ] && branch="feat/${n}-${slug}"
  case "$decision" in
    run-plan)
      # Runs in the clone main checkout: /plan writes the draft here.
      claude_run "$ROOT" "/plan ${n}"
      bash "$STORE" set-phase "$n" plan
      ;;
    run-implement)
      # Also the clone main checkout: /implement branches + creates the worktree from here.
      claude_run "$ROOT" "/implement ${ROOT}/.agents/plans/${slug}.plan.md"
      bash "$STORE" set-phase "$n" implement
      ;;
    run-validate)
      # The worktree once it exists (same root gather_snapshot reads), else the clone.
      dir="$(_artifact_root "$branch")"
      pp="$(_plan_path_in "$dir" "$slug")"
      claude_run "$dir" "/validate ${pp}"
      bash "$STORE" set-phase "$n" validate
      ;;
    open-pr)
      # Idempotent fallback: a green gate left no PR → re-run /validate (push+PR+notify).
      dir="$(_artifact_root "$branch")"
      pp="$(_plan_path_in "$dir" "$slug")"
      claude_run "$dir" "/validate ${pp}"
      ;;
    noop)
      : # terminal; main releases the claim
      ;;
    *)
      echo "dispatch: unknown decision '$decision'" >&2
      return 2
      ;;
  esac
}

# --- claim gate (a label, not an assignee) -----------------------------------
_claim()   { "$GH" issue edit "$1" --add-label    "$CLAIM_LABEL" >/dev/null 2>&1 || true; }
_release() { "$GH" issue edit "$1" --remove-label "$CLAIM_LABEL" >/dev/null 2>&1 || true; }

# --- decide: hand the snapshot to the pure decider (the ONLY policy) ----------
_field() { printf '%s\n' "$1" | grep -E "^$2=" | cut -d= -f2- || true; }
_decide() {  # snapshot-blob → decision on stdout; the decider's exit propagates
  local snap="$1"
  env -i \
    ISSUE_READY="$(_field "$snap" ISSUE_READY)" \
    PLAN_PRESENT="$(_field "$snap" PLAN_PRESENT)" \
    REPORT_PRESENT="$(_field "$snap" REPORT_PRESENT)" \
    GATE="$(_field "$snap" GATE)" \
    PR_OPEN="$(_field "$snap" PR_OPEN)" \
    ESCALATED="$(_field "$snap" ESCALATED)" \
    ATTEMPTS="$(_field "$snap" ATTEMPTS)" \
    MAX_ATTEMPTS="$MAX_ATTEMPTS_K" \
    bash "$DECIDER"
}

# --- run: selection → claim → bounded decide/dispatch loop --------------------
# The for-loop is a mechanical "keep asking the decider until noop" — it holds
# ZERO policy. Which action runs is 100% the decider's output.
run() {
  local n="$1" decision snap rc

  # Selection / claim gate (never double-grab; claim BEFORE any worktree).
  if _has_label "$n" "$CLAIM_LABEL"; then
    echo "skip: already claimed (#$n)"
    return 0
  fi
  if ! _has_label "$n" "$TRIGGER_LABEL"; then
    echo "skip: not ready (#$n)"
    return 0
  fi
  _claim "$n"

  local i
  for (( i = 1; i <= MAX_ITERS; i++ )); do
    snap="$(gather_snapshot "$n")"
    rc=0; decision="$(_decide "$snap")" || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "decider exited $rc for #$n (out of scope this slice)" >&2
      return "$rc"
    fi
    case "$decision" in
      noop)
        _release "$n"          # terminal (PR open) → drop the claim
        echo "done: #$n (released $CLAIM_LABEL)"
        return 0
        ;;
      run-plan|run-implement|run-validate|open-pr)
        dispatch "$decision" "$n"
        ;;
      *)
        echo "unexpected decision '$decision' for #$n" >&2
        return 4
        ;;
    esac
  done

  echo "iteration cap hit (#$n, MAX_ITERS=$MAX_ITERS)" >&2
  return 3
}

usage() {
  echo "usage: $(basename "$0") <issue-number>|run <N>|snapshot <N>|resolve-slug <N>|dispatch <decision> <N>" >&2
}

# --- subcommand entry --------------------------------------------------------
main() {
  local cmd="${1:-}"
  case "$cmd" in
    resolve-slug) resolve_slug "${2:?usage: resolve-slug <N>}" ;;
    snapshot)     gather_snapshot "${2:?usage: snapshot <N>}" ;;
    dispatch)     dispatch "${2:?usage: dispatch <decision> <N>}" "${3:?usage: dispatch <decision> <N>}" ;;
    run)          run "${2:?usage: run <N>}" ;;
    ''|-h|--help) usage ;;
    *)
      if printf '%s' "$cmd" | grep -qE '^[0-9]+$'; then
        run "$cmd"        # primary entry point: night_shift_run.sh <issue-number>
      else
        usage
        exit 2
      fi
      ;;
  esac
}

main "$@"
