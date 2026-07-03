#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/piv_check.sh"

TMPDIR_ROOT="$(mktemp -d /tmp/pivtest.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FAILURES=0

assert_pass() {
  local output="$1" msg="$2"
  if ! printf '%s' "$output" | grep -q "PIV checks passed"; then
    echo "FAIL: $msg (expected pass, got: $output)"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_skipped() {
  local output="$1" msg="$2"
  if ! printf '%s' "$output" | grep -q "skipped"; then
    echo "FAIL: $msg (expected skip, got: $output)"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_fail_contains() {
  local output="$1" pattern="$2" msg="$3"
  if printf '%s' "$output" | grep -q "PIV checks passed"; then
    echo "FAIL: $msg (expected failure but passed)"
    FAILURES=$((FAILURES + 1))
  elif ! printf '%s' "$output" | grep -qF "$pattern"; then
    echo "FAIL: $msg (expected '$pattern' in: $output)"
    FAILURES=$((FAILURES + 1))
  fi
}

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  touch "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "init"
}

add_plan() {
  local dir="$1" name="$2"
  mkdir -p "$dir/.agents/plans"
  echo "# plan" > "$dir/.agents/plans/${name}.plan.md"
  git -C "$dir" add ".agents/plans/${name}.plan.md"
  git -C "$dir" commit -q -m "docs(plan): add ${name}"
}

add_impl() {
  local dir="$1"
  echo "code" > "$dir/src.sh"
  git -C "$dir" add src.sh
  git -C "$dir" commit -q -m "feat: implement"
}

add_report() {
  local dir="$1" name="$2"
  mkdir -p "$dir/.agents/reports"
  echo "# report" > "$dir/.agents/reports/${name}-report.md"
  git -C "$dir" add ".agents/reports/${name}-report.md"
  git -C "$dir" commit -q -m "docs(report): add ${name}"
}

# --- Test (a): on main → skips (PIV checks don't enforce main directly) ---
REPO_A="$TMPDIR_ROOT/repo_a"
make_repo "$REPO_A"
output_a="$(cd "$REPO_A" && bash "$CHECK" 2>&1)"
assert_skipped "$output_a" "test(a): on main skips"

# --- Test (b): feature branch, no commits → passes (plan phase, pre-first-commit) ---
REPO_B="$TMPDIR_ROOT/repo_b"
make_repo "$REPO_B"
git -C "$REPO_B" checkout -q -b feat/issue-123
output_b="$(cd "$REPO_B" && bash "$CHECK" 2>&1)"
assert_pass "$output_b" "test(b): feature branch no commits passes"

# --- Test (c): plan is only commit → passes (end of plan phase) ---
REPO_C="$TMPDIR_ROOT/repo_c"
make_repo "$REPO_C"
git -C "$REPO_C" checkout -q -b feat/issue-123
add_plan "$REPO_C" "my-feature"
output_c="$(cd "$REPO_C" && bash "$CHECK" 2>&1)"
assert_pass "$output_c" "test(c): plan-only commit passes (plan phase)"

# --- Test (d): plan + impl + report → passes ---
REPO_D="$TMPDIR_ROOT/repo_d"
make_repo "$REPO_D"
git -C "$REPO_D" checkout -q -b feat/issue-123
add_plan "$REPO_D" "my-feature"
add_impl "$REPO_D"
add_report "$REPO_D" "my-feature"
output_d="$(cd "$REPO_D" && bash "$CHECK" 2>&1)"
assert_pass "$output_d" "test(d): plan + impl + report passes"

# --- Test (e): plan + impl, report missing → fails ---
REPO_E="$TMPDIR_ROOT/repo_e"
make_repo "$REPO_E"
git -C "$REPO_E" checkout -q -b feat/issue-123
add_plan "$REPO_E" "my-feature"
add_impl "$REPO_E"
output_e="$(cd "$REPO_E" && bash "$CHECK" 2>&1)" || true
assert_fail_contains "$output_e" "no matching report at .agents/reports/my-feature-report.md" "test(e): missing report fails"

# --- Test (f): plan archived to completed/ → passes (validate phase) ---
# Simulates full lifecycle: plan → impl → report + archive
REPO_F="$TMPDIR_ROOT/repo_f"
make_repo "$REPO_F"
git -C "$REPO_F" checkout -q -b feat/issue-123
add_plan "$REPO_F" "my-feature"
add_impl "$REPO_F"
add_report "$REPO_F" "my-feature"
# Validate archives the plan
mkdir -p "$REPO_F/.agents/plans/completed"
mv "$REPO_F/.agents/plans/my-feature.plan.md" "$REPO_F/.agents/plans/completed/my-feature.plan.md"
git -C "$REPO_F" add .agents/plans/
git -C "$REPO_F" commit -q -m "validate: archive plan"
output_f="$(cd "$REPO_F" && bash "$CHECK" 2>&1)"
assert_pass "$output_f" "test(f): archived plan passes (validate phase)"

# --- Test (g): first commit is not a plan → fails ---
REPO_G="$TMPDIR_ROOT/repo_g"
make_repo "$REPO_G"
git -C "$REPO_G" checkout -q -b feat/issue-123
echo "code" > "$REPO_G/src.sh"
git -C "$REPO_G" add src.sh
git -C "$REPO_G" commit -q -m "feat: implement without plan"
output_g="$(cd "$REPO_G" && bash "$CHECK" 2>&1)" || true
assert_fail_contains "$output_g" "plan file" "test(g): first commit not plan fails"

# --- Test (j): prd/* branch (no plan) → skips (non-PIV Phase 1, by prefix) ---
# Grill/strategic-planning output is non-PIV, like retroactive.
REPO_J="$TMPDIR_ROOT/repo_j"
make_repo "$REPO_J"
git -C "$REPO_J" checkout -q -b prd/some-feature
mkdir -p "$REPO_J/.agents/prds" "$REPO_J/docs/adr"
echo "# prd" > "$REPO_J/.agents/prds/some-feature.prd.md"
echo "# glossary" > "$REPO_J/CONTEXT.md"
echo "# adr" > "$REPO_J/docs/adr/0001-some-decision.md"
git -C "$REPO_J" add .agents/prds/ CONTEXT.md docs/adr/
git -C "$REPO_J" commit -q -m "docs(prd): add PRD, glossary, ADR"
output_j="$(cd "$REPO_J" && bash "$CHECK" 2>&1)"
assert_skipped "$output_j" "test(j): prd/* branch skips"

# --- Test (k): prd/* exempt by prefix even when it also touches machinery ---
# This is the bootstrap case: the commit that adds the exemption itself edits
# scripts/, yet must still be exempt.
REPO_K="$TMPDIR_ROOT/repo_k"
make_repo "$REPO_K"
git -C "$REPO_K" checkout -q -b prd/some-feature
mkdir -p "$REPO_K/.agents/prds" "$REPO_K/scripts"
echo "# prd" > "$REPO_K/.agents/prds/some-feature.prd.md"
echo "machinery" > "$REPO_K/scripts/piv_check.sh"
git -C "$REPO_K" add .agents/prds/ scripts/
git -C "$REPO_K" commit -q -m "docs(prd): prd plus harness fix"
output_k="$(cd "$REPO_K" && bash "$CHECK" 2>&1)"
assert_skipped "$output_k" "test(k): prd/* exempt by prefix despite machinery edit"

# --- Test (l): align/* branch (CONTEXT.md only) → skips ---
REPO_L="$TMPDIR_ROOT/repo_l"
make_repo "$REPO_L"
git -C "$REPO_L" checkout -q -b align/glossary
echo "# glossary" > "$REPO_L/CONTEXT.md"
git -C "$REPO_L" add CONTEXT.md
git -C "$REPO_L" commit -q -m "docs(context): resolve terms"
output_l="$(cd "$REPO_L" && bash "$CHECK" 2>&1)"
assert_skipped "$output_l" "test(l): align/* branch skips"

# --- Test (m): chore/* branch (no plan) → skips (maintenance, by prefix) ---
# Archiving completed designs / dep bumps have no plan/implement/validate cycle.
REPO_M="$TMPDIR_ROOT/repo_m"
make_repo "$REPO_M"
git -C "$REPO_M" checkout -q -b chore/archive-completed-designs
mkdir -p "$REPO_M/.agents/plans/completed"
echo "# plan" > "$REPO_M/.agents/plans/completed/old-feature.plan.md"
git -C "$REPO_M" add .agents/plans/completed/
git -C "$REPO_M" commit -q -m "chore(designs): archive completed plan"
output_m="$(cd "$REPO_M" && bash "$CHECK" 2>&1)"
assert_skipped "$output_m" "test(m): chore/* branch skips"

# --- Test (n): docs/* branch (no plan) → skips (doc edits, by prefix) ---
REPO_N="$TMPDIR_ROOT/repo_n"
make_repo "$REPO_N"
git -C "$REPO_N" checkout -q -b docs/fix-readme
echo "# readme" > "$REPO_N/README.md"
git -C "$REPO_N" add README.md
git -C "$REPO_N" commit -q -m "docs: clarify readme"
output_n="$(cd "$REPO_N" && bash "$CHECK" 2>&1)"
assert_skipped "$output_n" "test(n): docs/* branch skips"

# --- Test (h): not a git repo → skips (fail open) ---
BARE_H="$TMPDIR_ROOT/bare_h"
mkdir -p "$BARE_H"
output_h="$(cd "$BARE_H" && bash "$CHECK" 2>&1)"
if printf '%s' "$output_h" | grep -q "FAIL"; then
  echo "FAIL: test(h): non-git dir should skip, not fail"
  FAILURES=$((FAILURES + 1))
fi

# --- Test (i): detached HEAD → skips ---
REPO_I="$TMPDIR_ROOT/repo_i"
make_repo "$REPO_I"
git -C "$REPO_I" checkout -q "$(git -C "$REPO_I" rev-parse HEAD)"
output_i="$(cd "$REPO_I" && bash "$CHECK" 2>&1)"
assert_skipped "$output_i" "test(i): detached HEAD skips"

# --- Test (o): local main behind origin/main → plan still reads as first commit ---
# Reproduces the Night Shift #97 drift: a sibling PR (#95) squash-merged into
# origin/main mid-drive, but the clone's local main was never fast-forwarded, so
# the branch descends from origin/main while local main lags by one commit.
# Measuring against the stale LOCAL main mis-reads that already-integrated
# upstream commit as the branch's first commit and trips Check 1. Anchoring to
# the more-advanced integration ref (origin/main here) excludes it → plan is
# correctly seen as the first commit.
REPO_O="$TMPDIR_ROOT/repo_o"
make_repo "$REPO_O"                                   # local main = C0 (init)
git -C "$REPO_O" checkout -q -b upstream-sim
echo "sibling" > "$REPO_O/SIBLING.md"                 # unrelated upstream doc (#95)
git -C "$REPO_O" add SIBLING.md
git -C "$REPO_O" commit -q -m "docs: unrelated sibling landed upstream"
UPSTREAM_SHA="$(git -C "$REPO_O" rev-parse HEAD)"
git -C "$REPO_O" checkout -q main
# Record it as origin/main WITHOUT fast-forwarding local main (the drift).
git -C "$REPO_O" update-ref refs/remotes/origin/main "$UPSTREAM_SHA"
# Executor cuts the feature branch from the current integration line (origin/main),
# then seeds the plan as the branch's first commit.
git -C "$REPO_O" checkout -q -b feat/issue-97 "$UPSTREAM_SHA"
add_plan "$REPO_O" "state-gc"
output_o="$(cd "$REPO_O" && bash "$CHECK" 2>&1)"
assert_pass "$output_o" "test(o): branch off origin/main with local main behind → plan is first commit"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
