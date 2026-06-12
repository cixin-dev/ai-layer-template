# Plan: fix(unsync): remove symlinks installed from a different mount path

## Summary
`unlink_owned` in `unsync.sh` currently identifies ownership via an exact `readlink` comparison against `$src`. When `sync.sh` ran from a different filesystem path than `unsync.sh` (NFS cross-mount scenario), the exact comparison fails and owned symlinks are silently left behind. The fix adds a suffix-based fallback: if the exact path doesn't match, check whether the symlink target ends with the same `/.claude/{skills,commands}/name` suffix as `$src`. Because upstream symlinks point to paths like `/upstream/placeholder` that never contain `/.claude/`, there are no false positives. A new test (j) covers the cross-mount scenario end-to-end.

## User Story
As a developer who syncs from an NFS mount and unsyncs from a local checkout, I want `unsync.sh` to remove all symlinks it installed, so that my `~/.claude` stays clean regardless of which mount path I run the script from.

## Metadata
| Field | Value |
|-------|-------|
| Type | BUG_FIX |
| Complexity | LOW |
| Systems affected | `scripts/unsync.sh`, `scripts/unsync.test.sh` |
| Issue | #7 |

## Patterns to Follow

### Suffix extraction via parameter expansion
The existing script uses POSIX-compatible `${var#pattern}` and `[ ]` tests throughout. Use the same style. Bash `##` (longest prefix strip) is safe here — the script already uses `#!/usr/bin/env bash`:

```bash
# SOURCE: scripts/unsync.sh:48
if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
```

Extend this block; do not restructure the entire function.

### `case` for glob matching (no bashism `[[`)
The rest of the script uses single-bracket `[ ]` tests. Use `case` to avoid introducing `[[ ]]`:

```bash
case "$target" in
  *"/.claude$suffix") matched=1 ;;
esac
```

### Test helper pattern (all existing tests use these four helpers)
```bash
# SOURCE: scripts/unsync.test.sh:16-46
assert_file_not_exists "$CLAUDE_HOME_DIR/skills/piv-loop" "test(j): ..."
assert_file_exists     "$CLAUDE_HOME_DIR/skills/grill-with-docs" "test(j): ..."
```

### Test isolation via `setup_fixture`
Every test calls `setup_fixture` first to get a clean slate:
```bash
# SOURCE: scripts/unsync.test.sh:64-92
setup_fixture
SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/unsync.sh` | UPDATE | Add cross-mount suffix fallback to `unlink_owned` |
| `scripts/unsync.test.sh` | UPDATE | Add test (j): sync from REPO, unsync from REPO2 |

## Tasks

### Task 1: Extend `unlink_owned` with cross-mount suffix fallback

- **File**: `scripts/unsync.sh`
- **Action**: UPDATE
- **Lines to change**: `unlink_owned` function (lines 46–62)
- **Implement**:

  Replace the body of `unlink_owned` with:

  ```bash
  unlink_owned() {
    local src="$1" dst="$2"
    if [ -L "$dst" ]; then
      local target
      target="$(readlink "$dst")"
      local matched=0
      if [ "$target" = "$src" ]; then
        matched=1
      else
        # Cross-mount fallback: owned if target ends with the same /.claude/... suffix.
        # Uses ## (longest-prefix strip) so an earlier .claude segment in the path
        # doesn't confuse the match. Upstream links (e.g. /upstream/placeholder)
        # never contain /.claude/ so they can't match.
        local suffix
        suffix="${src##*/.claude}"
        if [ -n "$suffix" ]; then
          case "$target" in
            *"/.claude$suffix") matched=1 ;;
          esac
        fi
      fi
      if [ "$matched" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          note "would remove symlink: $dst"
        else
          rm -f "$dst"
          note "removed symlink: $dst"
        fi
      fi
      # else: symlink pointing elsewhere (upstream/user) → leave untouched
      return
    fi
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      note "skip: $dst is a real file/directory — not ours"
      return
    fi
    # absent → no-op
  }
  ```

- **Mirror**: `scripts/unsync.sh:46-62` (existing `unlink_owned`)
- **Validate**: `bash scripts/unsync.test.sh`

### Task 2: Add test (j) — cross-mount unsync

- **File**: `scripts/unsync.test.sh`
- **Action**: UPDATE
- **Lines to change**: append before the final `if [ "$FAILURES" -eq 0 ]` block (after test `i`, line ~218)
- **Implement**:

  ```bash
  # --- Test (j): cross-mount — sync from REPO, unsync from REPO2 (different path, same .claude/ layout) ---
  setup_fixture
  REPO2="$TMPDIR_ROOT/repo2"
  mkdir -p "$REPO2/.claude/skills/piv-loop" \
            "$REPO2/.claude/skills/system-evolution" \
            "$REPO2/.claude/skills/tdd-gate" \
            "$REPO2/.claude/commands" \
            "$REPO2/.claude/hooks"
  touch "$REPO2/.claude/skills/piv-loop/SKILL.md" \
        "$REPO2/.claude/skills/system-evolution/SKILL.md" \
        "$REPO2/.claude/skills/tdd-gate/SKILL.md" \
        "$REPO2/.claude/commands/plan.md" \
        "$REPO2/.claude/commands/implement.md" \
        "$REPO2/.claude/commands/retroactive.md" \
        "$REPO2/.claude/commands/validate.md"
  echo '#!/usr/bin/env python3' > "$REPO2/.claude/hooks/validate_gate.py"
  echo '#!/usr/bin/env python3' > "$REPO2/.claude/hooks/security_guard.py"
  # Sync from REPO1, unsync from REPO2 — simulates NFS vs local checkout
  SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null
  SYNC_REPO_DIR="$REPO2" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$UNSYNC_SH" >/dev/null
  assert_file_not_exists "$CLAUDE_HOME_DIR/skills/piv-loop"         "test(j): piv-loop removed (cross-mount)"
  assert_file_not_exists "$CLAUDE_HOME_DIR/skills/system-evolution" "test(j): system-evolution removed (cross-mount)"
  assert_file_not_exists "$CLAUDE_HOME_DIR/skills/tdd-gate"         "test(j): tdd-gate removed (cross-mount)"
  assert_file_not_exists "$CLAUDE_HOME_DIR/commands/plan.md"        "test(j): plan.md removed (cross-mount)"
  assert_file_not_exists "$CLAUDE_HOME_DIR/commands/implement.md"   "test(j): implement.md removed (cross-mount)"
  assert_file_exists "$CLAUDE_HOME_DIR/skills/grill-with-docs" "test(j): grill-with-docs untouched (cross-mount)"
  assert_file_exists "$CLAUDE_HOME_DIR/skills/to-prd"          "test(j): to-prd untouched (cross-mount)"
  assert_file_exists "$CLAUDE_HOME_DIR/skills/grill-me"        "test(j): grill-me untouched (cross-mount)"
  assert_file_exists "$CLAUDE_HOME_DIR/skills/to-issues"       "test(j): to-issues untouched (cross-mount)"
  ```

- **Mirror**: `scripts/unsync.test.sh:211-218` (test `i` pattern)
- **Validate**: `bash scripts/unsync.test.sh`

## Validation
```bash
bash scripts/unsync.test.sh
```
Expected: `All tests passed.` (tests a–j, exit 0)

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `bash scripts/unsync.test.sh` exits 0 with `All tests passed.`
- [ ] Follows existing single-bracket / `case` style — no `[[ ]]` introduced
- [ ] New test (j): sync from `$REPO`, unsync from `$REPO2` — all owned symlinks removed, upstream symlinks survive
- [ ] Upstream symlinks (`/upstream/placeholder`) are never matched by the suffix fallback
