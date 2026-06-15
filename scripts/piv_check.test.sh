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

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
