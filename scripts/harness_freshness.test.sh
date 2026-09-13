#!/usr/bin/env bash
# Test seam for .claude/hooks/harness_freshness.sh — proves each check flips
# green→red for the RIGHT reason against a known-good and a known-bad fixture,
# with the return code asserted exactly: rc 1 is the script's own strict-fail
# path; rc 126/127 would mean it never ran (a forged flip — CLAUDE.md
# "Verification-led").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/harness_freshness.sh"

TMPDIR_ROOT="$(mktemp -d /tmp/hftest.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

SEED="$TMPDIR_ROOT/seed"            # where "upstream" commits are authored
UPSTREAM="$TMPDIR_ROOT/upstream.git" # bare remote both sides push/fetch
SRC="$TMPDIR_ROOT/src"              # the operator's checkout the symlinks point into
CLAUDE_HOME_DIR="$TMPDIR_ROOT/claude_home"

FAILURES=0
FETCH_MINUTES=0   # throttle off by default so every case fetches; case (3) flips it

assert_contains() {
  local output="$1" pattern="$2" msg="$3"
  if ! printf '%s' "$output" | grep -qF -- "$pattern"; then
    echo "FAIL: $msg"
    echo "  expected to contain: $pattern"
    echo "  output: $output"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_contains() {
  local output="$1" pattern="$2" msg="$3"
  if printf '%s' "$output" | grep -qF -- "$pattern"; then
    echo "FAIL: $msg"
    echo "  expected NOT to contain: $pattern"
    echo "  output: $output"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_rc() {
  local got="$1" want="$2" msg="$3"
  if [ "$got" -ne "$want" ]; then
    echo "FAIL: $msg (rc $got, want $want)"
    FAILURES=$((FAILURES + 1))
  fi
}

# run [args...] → sets OUT and RC. Stdin carries a SessionStart-shaped JSON blob,
# as Claude Code does, to prove the hook never blocks reading it.
run() {
  RC=0
  OUT="$(printf '{"hook_event_name":"SessionStart"}' \
    | CLAUDE_HOME="$CLAUDE_HOME_DIR" HARNESS_FRESHNESS_FETCH_MINUTES="$FETCH_MINUTES" \
      PATH="${HOOK_PATH:-$PATH}" bash "$HOOK" "$@" 2>&1)" || RC=$?
}

setup_fixture() {
  rm -rf "$SEED" "$UPSTREAM" "$SRC" "$CLAUDE_HOME_DIR" "$TMPDIR_ROOT/plain"

  # A source repo with one skill, one command, one hook — pushed to a bare upstream.
  mkdir -p "$SEED/.claude/skills/foo" "$SEED/.claude/commands" "$SEED/.claude/hooks"
  echo 'skill' > "$SEED/.claude/skills/foo/SKILL.md"
  echo 'command' > "$SEED/.claude/commands/bar.md"
  echo '#!/usr/bin/env python3' > "$SEED/.claude/hooks/h.py"
  git -C "$SEED" init -q -b main
  git -C "$SEED" config user.email "test@test.com"
  git -C "$SEED" config user.name "Test"
  git -C "$SEED" add -A
  git -C "$SEED" commit -q -m "init"
  git clone -q --bare "$SEED" "$UPSTREAM"
  git -C "$SEED" remote add origin "$UPSTREAM"

  # The operator's checkout: tracks origin/main, origin/HEAD resolves.
  git clone -q "$UPSTREAM" "$SRC"
  git -C "$SRC" config user.email "test@test.com"
  git -C "$SRC" config user.name "Test"

  # User scope: per-item symlinks (ADR-0007) + a real-file hook copy (ADR-0012).
  mkdir -p "$CLAUDE_HOME_DIR/skills" "$CLAUDE_HOME_DIR/commands" "$CLAUDE_HOME_DIR/hooks"
  ln -s "$SRC/.claude/skills/foo"      "$CLAUDE_HOME_DIR/skills/foo"
  ln -s "$SRC/.claude/commands/bar.md" "$CLAUDE_HOME_DIR/commands/bar.md"
  cp "$SRC/.claude/hooks/h.py" "$CLAUDE_HOME_DIR/hooks/h.py"

  # A symlink into a plain (non-git) dir — must be ignored, never a finding.
  mkdir -p "$TMPDIR_ROOT/plain"
  ln -s "$TMPDIR_ROOT/plain" "$CLAUDE_HOME_DIR/skills/plain"
}

# One new commit lands on the upstream that SRC has not pulled.
advance_upstream() {
  echo "$1" >> "$SEED/.claude/commands/bar.md"
  git -C "$SEED" commit -q -am "$1"
  git -C "$SEED" push -q origin main
}

# --- (1) known-good: in sync, on main, clean, links resolve, hook copy identical ---
setup_fixture
run --strict
assert_rc "$RC" 0 "test(1): known-good --strict exits 0"
assert_contains "$OUT" "fresh" "test(1): known-good --strict reports fresh"
assert_not_contains "$OUT" "plain" "test(1): non-git link target is never a finding"
run
assert_rc "$RC" 0 "test(1): known-good hook mode exits 0"
if [ -n "$OUT" ]; then
  echo "FAIL: test(1): known-good hook mode must print nothing (no alarm fatigue), got: $OUT"
  FAILURES=$((FAILURES + 1))
fi

# --- (2) behind upstream: --strict rc exactly 1; hook mode still exits 0 but reports ---
setup_fixture
advance_upstream "one"
run --strict
assert_rc "$RC" 1 "test(2): behind --strict exits 1"
assert_contains "$OUT" "1 commit(s) behind origin/main" "test(2): names the count and the upstream"
assert_contains "$OUT" "$SRC" "test(2): names the repo"
# Two links (a skill and a command) point into the same repo → one finding, not two.
behind_count=$(printf '%s\n' "$OUT" | grep -c "behind origin/main" || true)
if [ "$behind_count" -ne 1 ]; then
  echo "FAIL: test(2): repo reported $behind_count times (want 1 — links into one repo dedupe)"
  FAILURES=$((FAILURES + 1))
fi
run
assert_rc "$RC" 0 "test(2): hook mode never blocks a session (exit 0 despite findings)"
assert_contains "$OUT" "1 commit(s) behind" "test(2): hook mode still reports the finding"

# --- (3) fetch throttle: a fresh FETCH_HEAD suppresses the fetch; 0 forces it ---
# Continues from (2): the runs above fetched, so FETCH_HEAD is seconds old.
advance_upstream "two"
FETCH_MINUTES=1440
run --strict
assert_contains "$OUT" "1 commit(s) behind" "test(3): throttled run reuses the recent fetch (still sees 1)"
FETCH_MINUTES=0
run --strict
assert_contains "$OUT" "2 commit(s) behind" "test(3): unthrottled run fetches and sees both"

# --- (4) unreachable upstream: fetch fails → fail open, no spurious finding, no hang ---
setup_fixture
git -C "$SRC" remote set-url origin "$TMPDIR_ROOT/nonexistent.git"
run --strict
assert_rc "$RC" 0 "test(4): unreachable upstream fails open (rc 0)"

# --- (5) source checkout on a feature branch → downstream runs unreviewed edits ---
setup_fixture
git -C "$SRC" checkout -q -b feat/x
run --strict
assert_rc "$RC" 1 "test(5): feature branch --strict exits 1"
assert_contains "$OUT" "on 'feat/x', not 'main'" "test(5): names the branch and the default"

# --- (6) dirty working tree ---
setup_fixture
echo "local edit" >> "$SRC/.claude/commands/bar.md"
run --strict
assert_rc "$RC" 1 "test(6): dirty tree --strict exits 1"
assert_contains "$OUT" "working tree dirty" "test(6): names the dirty state"

# --- (7) dangling symlink in user scope ---
setup_fixture
ln -s "$TMPDIR_ROOT/nowhere" "$CLAUDE_HOME_DIR/skills/gone"
run --strict
assert_rc "$RC" 1 "test(7): dangling link --strict exits 1"
assert_contains "$OUT" "dangling symlink: $CLAUDE_HOME_DIR/skills/gone" "test(7): names the dangling link"

# --- (8) hook copy stale: source changed (committed, so the tree stays clean) ---
setup_fixture
echo '# newer' >> "$SRC/.claude/hooks/h.py"
git -C "$SRC" commit -q -am "hook change"
run --strict
assert_rc "$RC" 1 "test(8): stale hook copy --strict exits 1"
assert_contains "$OUT" "hook copy stale: $CLAUDE_HOME_DIR/hooks/h.py" "test(8): names the stale copy"
assert_contains "$OUT" "sync.sh" "test(8): tells the operator the remedy"

# --- (9) hook copy missing ---
setup_fixture
rm "$CLAUDE_HOME_DIR/hooks/h.py"
run --strict
assert_rc "$RC" 1 "test(9): missing hook copy --strict exits 1"
assert_contains "$OUT" "hook copy missing: $CLAUDE_HOME_DIR/hooks/h.py" "test(9): names the missing copy"

# --- (12) PATH `claude` is not the local install: scripts and cron get the PATH one ---
# A ~/.bashrc alias hid a root-owned npm-global 1.0.8 on PATH behind
# ~/.claude/local/claude 2.1.269; night_shift_run.sh (bare `claude`) resolved 1.0.8.
setup_fixture
mkdir -p "$CLAUDE_HOME_DIR/local" "$TMPDIR_ROOT/stalebin"
printf '#!/usr/bin/env bash\necho "2.1.269 (Claude Code)"\n' > "$CLAUDE_HOME_DIR/local/claude"
printf '#!/usr/bin/env bash\necho "1.0.8 (Claude Code)"\n'   > "$TMPDIR_ROOT/stalebin/claude"
chmod +x "$CLAUDE_HOME_DIR/local/claude" "$TMPDIR_ROOT/stalebin/claude"
HOOK_PATH="$TMPDIR_ROOT/stalebin:$PATH"
run --strict
assert_rc "$RC" 1 "test(12): stale PATH claude --strict exits 1"
assert_contains "$OUT" "PATH claude is $TMPDIR_ROOT/stalebin/claude (1.0.8)" "test(12): names the PATH binary and its version"
assert_contains "$OUT" "$CLAUDE_HOME_DIR/local/claude (2.1.269)" "test(12): names the local install and its version"

# --- (13) PATH claude IS the local install (a symlink to it) → no finding ---
mkdir -p "$TMPDIR_ROOT/goodbin"
ln -sf "$CLAUDE_HOME_DIR/local/claude" "$TMPDIR_ROOT/goodbin/claude"
HOOK_PATH="$TMPDIR_ROOT/goodbin:$PATH"
run --strict
assert_rc "$RC" 0 "test(13): PATH claude linked to the local install is fresh"
unset HOOK_PATH

# --- (14) Skill-tool dependency missing: a linked skill calls a skill that is not linked ---
# Hand-picked symlinks (ADR-0007) miss shared deps silently: grill-me / grill-with-docs /
# triage sat broken on "grilling" / "domain-modeling" (retroactive: skill-dep-closure).
# The "twice, for" form carries two names; one resolves, one doesn't → exactly one finding.
setup_fixture
mkdir -p "$CLAUDE_HOME_DIR/skills/present"
printf -- '---\nname: present\ndescription: model-invoked\n---\nbody\n' > "$CLAUDE_HOME_DIR/skills/present/SKILL.md"
echo 'Call the Skill tool twice, for "present" and "absent".' >> "$SRC/.claude/skills/foo/SKILL.md"
git -C "$SRC" commit -q -am "foo depends on present + absent"
run --strict
assert_rc "$RC" 1 "test(14): missing skill dependency --strict exits 1"
assert_contains "$OUT" "skill dependency missing: $CLAUDE_HOME_DIR/skills/foo/SKILL.md calls the Skill tool with \"absent\"" "test(14): names the caller and the missing dependency"
assert_not_contains "$OUT" '"present"' "test(14): a resolved, model-invoked dependency is never a finding"
dep_count=$(printf '%s\n' "$OUT" | grep -c "skill dependency" || true)
if [ "$dep_count" -ne 1 ]; then
  echo "FAIL: test(14): $dep_count dependency findings (want exactly 1 — only the absent one)"
  FAILURES=$((FAILURES + 1))
fi

# --- (15) dependency linked → green (the same fixture, dependency now present) ---
mkdir -p "$CLAUDE_HOME_DIR/skills/absent"
printf -- '---\nname: absent\ndescription: model-invoked\n---\nbody\n' > "$CLAUDE_HOME_DIR/skills/absent/SKILL.md"
run --strict
assert_rc "$RC" 0 "test(15): once every dependency is linked and model-invoked, --strict exits 0"

# --- (16) dependency is user-invoked (disable-model-invocation: true) → unreachable ---
# The harness drops user-invoked skills from the model's listing, so no skill can reach one
# via the Skill tool (probed 2026-09-13: "cannot be used with Skill tool"). Only the human can.
printf -- '---\nname: absent\ndescription: human-only\ndisable-model-invocation: true\n---\nbody\n' > "$CLAUDE_HOME_DIR/skills/absent/SKILL.md"
run --strict
assert_rc "$RC" 1 "test(16): user-invoked dependency --strict exits 1"
assert_contains "$OUT" "skill dependency unreachable: $CLAUDE_HOME_DIR/skills/foo/SKILL.md calls the Skill tool with \"absent\"" "test(16): names the caller and the unreachable dependency"
assert_contains "$OUT" "tell the user to run /absent" "test(16): tells the author the remedy"

# --- (17) a command (not only a skill) that calls an unlinked skill is also a finding ---
setup_fixture
echo 'Call the Skill tool with "nowhere".' >> "$SRC/.claude/commands/bar.md"
git -C "$SRC" commit -q -am "bar depends on nowhere"
run --strict
assert_rc "$RC" 1 "test(17): command with missing skill dependency --strict exits 1"
assert_contains "$OUT" "skill dependency missing: $CLAUDE_HOME_DIR/commands/bar.md calls the Skill tool with \"nowhere\"" "test(17): names the command and the missing dependency"

# --- (10) empty user scope (fresh machine): nothing to check → rc 0 ---
rm -rf "$CLAUDE_HOME_DIR"
mkdir -p "$CLAUDE_HOME_DIR"
run --strict
assert_rc "$RC" 0 "test(10): empty user scope exits 0"

# --- (11) unknown option → rc 2 (a typo must not pass as green) ---
run --bogus
assert_rc "$RC" 2 "test(11): unknown option exits 2"

if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
