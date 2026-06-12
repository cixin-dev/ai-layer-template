# Report: hooks-copy-not-symlink-nfs-resilient

## Tasks Completed

- ✅ Task 1: Added `copy_item` to `scripts/sync.sh`; routed hooks loop through it; updated header comment.
- ✅ Task 2: Updated existing hook tests for copy semantics (test b, d, f); added `assert_not_symlink` and `assert_executable` helpers.
- ✅ Task 3: Added test (i) — migration test proving symlink-into-NFS pre-state becomes real, executable, repo-matching files.
- ✅ Task 4: Created ADR-0012; updated ADR-0007 Status.

## Validation Results

- `bash .claude/validate.sh` → `All tests passed.`
- Manual dry-run: hooks show `would copy:`, skills/commands show `would link:` ✓

## Files Changed

| File | Change |
|------|--------|
| `scripts/sync.sh` | Added `copy_item` function; routed hooks loop; updated header comment |
| `scripts/sync.test.sh` | Added `assert_not_symlink`/`assert_executable` helpers; updated tests b, d, f; added test (i) |
| `docs/adr/0012-hooks-copied-not-symlinked-for-nfs-resilience.md` | Created |
| `docs/adr/0007-sync-machinery-to-user-scope-by-per-item-symlink.md` | Added partial-supersede Status line |

## Tests Written

- `assert_not_symlink` and `assert_executable` helpers (mirroring existing `assert_*` pattern)
- Test (i): migration from symlink-into-NFS to real, executable, repo-matching files (issue #2 acceptance criteria)

## Deviations from Plan

None. All patterns, function signatures, and test conventions match the plan exactly.

## Branch

`feat/3-hooks-copy-not-symlink-nfs-resilient`
