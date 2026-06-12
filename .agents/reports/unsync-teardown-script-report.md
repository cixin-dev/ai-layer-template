# Report: unsync.sh teardown script

## Tasks completed

| # | Task | Status |
|---|------|--------|
| 1 | Create `scripts/unsync.sh` | ✅ |
| 2 | Create `scripts/unsync.test.sh` | ✅ |
| 3 | Wire `unsync.test.sh` into `.claude/validate.sh` | ✅ |
| 4 | Document `unsync.sh` in `README.md` | ✅ |

## Validation results

- `bash -n scripts/unsync.sh` — syntax OK
- `bash scripts/unsync.sh --help` — prints usage
- `bash scripts/unsync.sh --bad` — exits 2
- `bash scripts/unsync.test.sh` — `All tests passed.` (9 test cases a–i)
- `bash .claude/validate.sh` — both suites pass, exit 0

## Files changed

| File | Action |
|------|--------|
| `scripts/unsync.sh` | CREATED (130 lines) |
| `scripts/unsync.test.sh` | CREATED (175 lines) |
| `.claude/validate.sh` | UPDATED (exec→sequential; runs both suites) |
| `README.md` | UPDATED (tree + usage section) |

## Tests written (unsync.test.sh)

- **(a)** dry-run is read-only — symlinks/hooks/settings unchanged
- **(b)** idempotency — second run: no removed/unwired output, exit 0
- **(c)** upstream safety — grill-with-docs, to-prd, grill-me, to-issues untouched
- **(d)** removes owned symlinks — all skills/commands removed; upstream intact
- **(e)** removes hook copies — both hooks gone after real run
- **(f)** restore from `.bak` — user theme key preserved; hook entries gone; `.bak` consumed
- **(g)** surgical removal (no `.bak`) — hook entries removed; no `.bak` created; idempotent on second run
- **(h)** unexpected state — directory at hook path → non-zero exit + clear message; other hook still removed
- **(i)** preserve user real file — real file at owned command path survives

## Deviations from plan

- `assert_file_exists` in test harness uses `[ ! -e "$path" ] && [ ! -L "$path" ]` (instead of just `-e`) to handle dangling symlinks (the upstream `/upstream/placeholder` symlinks). The plan did not mention this but it was necessary for correctness and mirrors the intent.
- No other deviations.
