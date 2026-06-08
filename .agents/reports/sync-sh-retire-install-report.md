# Report: sync.sh + retire install.sh + dry-run tests

## Tasks Completed

- ✅ Task 1: Created `scripts/sync.sh` — dynamic symlink installer with `--dry-run`
- ✅ Task 2: Deleted `scripts/install.sh` via `git rm`
- ✅ Task 3: Created `scripts/sync.test.sh` — self-contained bash assertion test

## Validation Results

```
bash -n scripts/sync.sh      → OK
bash -n scripts/sync.test.sh → OK
bash scripts/sync.test.sh    → All tests passed.
ls scripts/                  → sync.sh  sync.test.sh  (install.sh absent)
```

All acceptance criteria pass:

- [x] `scripts/sync.sh` exists and is executable bash (`bash -n` passes)
- [x] `scripts/install.sh` is deleted (git rm'd)
- [x] `scripts/sync.test.sh` exists and exits 0
- [x] Test (a): fresh-state dry-run output mentions every owned skill and command
- [x] Test (b): idempotent dry-run output contains no `would link:` lines
- [x] Test (c): upstream names never appear in sync.sh output
- [x] Owned-items list is dynamic: no hardcoded skill/command names
- [x] Occupied-target policy: real file/dir → warn + skip; stale symlink → relink

## Files Changed

| File | Action |
|------|--------|
| `scripts/sync.sh` | Created (66 lines) |
| `scripts/sync.test.sh` | Created (72 lines) |
| `scripts/install.sh` | Deleted (git rm) |

## Deviations from Plan

None. Implementation follows the plan exactly.

## Tests Written

`scripts/sync.test.sh` covers:
- (a) Fresh-state dry-run: all 3 skills + 3 commands appear in output
- (b) Idempotency: no `would link:` when symlinks already correct
- (c) Upstream safety: 4 upstream names (`grill-with-docs`, `to-prd`, `grill-me`, `to-issues`) never appear

## Branch

`feat/01-sync-sh-retire-install`

## Next Step

Human review in a fresh session, then open a PR.
