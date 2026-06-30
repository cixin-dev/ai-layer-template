# Plan: Night Shift Probe — One-Line Greeting Helper

## Summary
Throwaway end-to-end probe for the Night Shift executor (Issue #73). Add a trivial,
self-contained bash helper `scripts/greeting.sh` that prints a one-line greeting, plus its
deterministic companion test `scripts/greeting.test.sh`, and wire that test into CI so the
full executor path (plan → implement → validate → PR → CI) is exercised. The PR will be
**closed unmerged** — the artifact's value is proving the loop works, not the helper itself.

## User Story
As a Night Shift operator I want a disposable issue to flow through the whole executor so
that I can confirm plan → implement → validate → PR → CI all work end-to-end before trusting
the automation with real work.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW |
| Complexity | LOW |
| Systems affected | `scripts/` (new helper + test), `.github/workflows/ci.yml` (test wiring) |
| Issue | #73 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| `name="${1:-world}"; echo "Hello, ${name}!"` prints `Hello, world!` with no arg and `Hello, Night Shift!` with arg `Night Shift` | **VERIFIED** | Ran a `/tmp` spike of the exact body: `bash spike.sh` → `Hello, world!`; `bash spike.sh "Night Shift"` → `Hello, Night Shift!` |
| Repo test convention is `scripts/foo.sh` + `scripts/foo.test.sh`, self-contained, `FAILURES` counter, `check()` helper, ends with `All tests passed.` / `N test(s) failed.` then `exit "$FAILURES"` | **VERIFIED** | Read `scripts/worktree_path.test.sh:1-69` — exact shape mirrored below |
| The validate gate (`.claude/validate.sh`) runs `piv_check.sh` only, NOT the unit tests | **VERIFIED** | Read `.claude/validate.sh` (runs `piv_check.sh`) — so the new test must be run explicitly (per-task) and wired into CI to actually execute |
| Every `scripts/*.test.sh` is run by CI via an explicit line in `ci.yml` (no auto-discovery) | **VERIFIED** | Read `.github/workflows/ci.yml:18-26` — all 9 tests listed explicitly; an unwired test would never run |
| `piv_check.sh` requires the **first** branch commit to add `.agents/plans/*.plan.md`, and once non-`.agents/` files change, a report must exist at `.agents/reports/{plan_name}-report.md` | **VERIFIED** | Read `scripts/piv_check.sh:62-86` — plan name `ns-probe-greeting-helper` ⇒ report `.agents/reports/ns-probe-greeting-helper-report.md` |
| Night Shift is quiesced, so this `/plan` (writes only an untracked plan file, no HEAD mutation) is safe in the main checkout | **VERIFIED** | `git worktree list` shows only the main checkout; tree clean on `main`; no `.night-shift/` loop-state dir present (HEAD-race checklist in CLAUDE.md satisfied) |

## Patterns to Follow

### Helper shape (minimal, self-contained, `set -euo pipefail`)
```bash
# SOURCE: scripts/worktree_path.sh:1-22 (header comment + strict mode + ${1:?}/${1:-} arg)
#!/usr/bin/env bash
# <one-line purpose>
set -euo pipefail
branch="${1:?usage: ...}"
```

### Test shape (deterministic, drives the helper directly)
```bash
# SOURCE: scripts/worktree_path.test.sh:1-69
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/worktree_path.sh"
FAILURES=0
check() {
  local expected="$1" branch="$2" desc="$3" output
  output="$(printf '%s\n' "$PORCELAIN" | bash "$RESOLVE" "$branch")"
  if [ "$output" != "$expected" ]; then
    echo "FAIL: $desc (expected '$expected', got '$output')"
    FAILURES=$((FAILURES + 1))
  fi
}
# ...
if [ "$FAILURES" -eq 0 ]; then echo "All tests passed."; else echo "$FAILURES test(s) failed."; fi
exit "$FAILURES"
```

### CI wiring (one line per test, no discovery)
```yaml
# SOURCE: .github/workflows/ci.yml:18-26
          bash scripts/night_shift_retry.test.sh
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/greeting.sh` | CREATE | One-line greeting helper; optional first arg (name), defaults to `world` |
| `scripts/greeting.test.sh` | CREATE | Self-contained deterministic test for both arg cases |
| `.github/workflows/ci.yml` | UPDATE | Add `bash scripts/greeting.test.sh` so CI runs the probe test |

## Tasks
Ordered, atomic, each independently verifiable.

### Task 1: Create the greeting helper
- File: `scripts/greeting.sh`
- Action: CREATE
- Implement: shebang + header comment naming Issue #73 and "throwaway / closed unmerged";
  `set -euo pipefail`; `name="${1:-world}"`; `echo "Hello, ${name}!"`. No other logic.
- Mirror: `scripts/worktree_path.sh:1-22`
- Validate: `bash scripts/greeting.sh` prints `Hello, world!`; `bash scripts/greeting.sh "Night Shift"` prints `Hello, Night Shift!`

### Task 2: Create the companion test
- File: `scripts/greeting.test.sh`
- Action: CREATE
- Implement: mirror the `worktree_path.test.sh` skeleton — `SCRIPT_DIR`/path resolution,
  `FAILURES=0`, a `check()` helper, two cases:
  - `check "Hello, world!" "defaults to world when no name given"` (no arg)
  - `check "Hello, Night Shift!" "greets the first-arg name" "Night Shift"`
  End with the standard `All tests passed.` / `N test(s) failed.` footer and `exit "$FAILURES"`.
- Mirror: `scripts/worktree_path.test.sh:1-69`
- Validate: `bash scripts/greeting.test.sh` → `All tests passed.`, exit 0

### Task 3: Wire the test into CI
- File: `.github/workflows/ci.yml`
- Action: UPDATE
- Implement: append `          bash scripts/greeting.test.sh` after the last existing test
  line (`night_shift_retry.test.sh`), matching the surrounding indentation exactly.
- Mirror: `.github/workflows/ci.yml:18-26`
- Validate: `bash -n` is not applicable to YAML; confirm with
  `grep -n 'greeting.test.sh' .github/workflows/ci.yml` and visual diff (indentation aligns).

## Validation
- **Unit test (project check for this slice):** `bash scripts/greeting.test.sh` → prints
  `All tests passed.` and exits 0.
- **Helper smoke:** `bash scripts/greeting.sh` → `Hello, world!`;
  `bash scripts/greeting.sh "Night Shift"` → `Hello, Night Shift!`.
- **Gate:** `bash .claude/validate.sh` (runs `piv_check.sh`) → `PIV checks passed.`
  (requires: first branch commit adds this plan file; report exists at
  `.agents/reports/ns-probe-greeting-helper-report.md` once code lands).
- **CI line present:** `grep -n 'bash scripts/greeting.test.sh' .github/workflows/ci.yml`
  returns the new line.
- **End-to-end (the actual probe):** PR opens, CI `test` job goes green, then the issue/PR
  is **closed unmerged** (per the issue — this verifies the executor, the helper is not kept).

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `bash scripts/greeting.test.sh` passes with zero errors (exit 0)
- [ ] Follows existing `scripts/*.sh` + `*.test.sh` convention
- [ ] Every external-behavior claim is VERIFIED by a probe (greeting output spike run)
- [ ] CI runs the new test (line present in `ci.yml`) and the `test` job is green
- [ ] End-to-end: PR opened; after green CI the issue/PR is closed unmerged
