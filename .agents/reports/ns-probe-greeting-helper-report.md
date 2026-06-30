# Report: Night Shift Probe — One-Line Greeting Helper

**Plan**: `.agents/plans/ns-probe-greeting-helper.plan.md`
**Issue**: #73
**Branch**: `feat/73-ns-probe-greeting-helper`

## Summary
Throwaway end-to-end probe for the Night Shift executor. Added a self-contained bash
greeting helper, its deterministic companion test, and wired the test into CI so the full
executor path (plan → implement → validate → PR → CI) is exercised. Per the issue, the PR is
to be **closed unmerged** — the artifact's value is proving the loop works, not the helper.

## Tasks Completed
| # | Task | Status |
|---|------|--------|
| 1 | Create `scripts/greeting.sh` (one-line greeting, optional name arg → defaults to `world`) | ✅ |
| 2 | Create `scripts/greeting.test.sh` (deterministic test, both arg cases) | ✅ |
| 3 | Wire `bash scripts/greeting.test.sh` into `.github/workflows/ci.yml` | ✅ |

## Validation Results
- **Helper smoke** — `bash scripts/greeting.sh` → `Hello, world!`;
  `bash scripts/greeting.sh "Night Shift"` → `Hello, Night Shift!` ✅
- **Unit test** — `bash scripts/greeting.test.sh` → `All tests passed.`, exit 0 ✅
- **CI line present** — `grep -n 'bash scripts/greeting.test.sh' .github/workflows/ci.yml`
  returns line 27; indentation aligns with sibling test lines ✅
- **Gate** — `bash .claude/validate.sh` (runs `piv_check.sh`) → `PIV checks passed.` ✅
  (first branch commit adds the plan file; report exists at this path)

## Files Changed
| File | Action |
|------|--------|
| `scripts/greeting.sh` | CREATE |
| `scripts/greeting.test.sh` | CREATE |
| `.github/workflows/ci.yml` | UPDATE (one test line appended) |
| `.agents/plans/ns-probe-greeting-helper.plan.md` | ADD (branch's first commit) |
| `.agents/reports/ns-probe-greeting-helper-report.md` | ADD (this report) |

## Tests Written
- `scripts/greeting.test.sh` — two deterministic cases:
  - defaults to `world` when no name given → `Hello, world!`
  - greets the first-arg name → `Hello, Night Shift!`

## Deviations from Plan
- **`check()` signature.** The plan's mirror (`worktree_path.test.sh`) drives its helper via
  stdin (`PORCELAIN | bash …`); the greeting helper instead takes the name as a direct
  positional arg. So `check()` is `check <expected> <desc> [name-arg...]` and invokes
  `bash "$GREETING" "$@"` rather than piping a fixture. Same skeleton (FAILURES counter,
  `All tests passed.` / `N test(s) failed.` footer, `exit "$FAILURES"`); only the
  drive mechanism differs to match the helper's interface. No behavioral impact.

## Next Step
`/validate .agents/plans/ns-probe-greeting-helper.plan.md` in a fresh session, then open the
PR. Per Issue #73 the PR is **closed unmerged** after CI goes green.
