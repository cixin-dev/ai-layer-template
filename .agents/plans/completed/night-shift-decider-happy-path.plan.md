# Plan: Night Shift next-action decider (pure) — happy-path decisions

## Summary
Build the pure **next-action decider** at the heart of the Night Shift loop: a bash script
(`scripts/night_shift_decide.sh`) that takes a task-state snapshot as explicit inputs (env
vars), and echoes exactly one next-action token from a closed set. It has **no side effects**
— it reads no git/fs, spawns no session, pushes nothing, notifies nothing; the snapshot is
*handed to it* (the impure git/fs gathering is the executor's job, a later slice). This slice
wires only the **happy-path** branches (`run-plan`, `run-implement`, `run-validate`,
`open-pr`, `noop`); the failure members (`retry-reimplement | retry-replan | escalate`) are
the closed-set *output type* but are out of scope here. The decider mirrors the shape of
`scripts/piv_check.sh` (objective state → verdict) and the table-driven subprocess test style
of `scripts/piv_check.test.sh`. This is the literal embodiment of ADR-0023: a mechanical
scheduler that *schedules* a phase from objective artifact facts and never *judges* semantic
completion.

## User Story
As a maintainer, I want the loop's next-action logic isolated as a pure decider, so that I
can exhaustively test the state machine offline without spawning sessions or spending tokens.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW |
| Complexity | LOW |
| Systems affected | `scripts/` (new decider + test), `.github/workflows/ci.yml` (register test) |
| Issue | #56 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| The happy-path precedence chain (terminal → gate → report → plan → ready → noop) yields the correct decision for every in-scope edge and stays consistent when multiple flags are true | **VERIFIED** | Throwaway spike `spike_decide.sh` ran 11 cases (5 happy edges + 2 terminals + 3 precedence-stress + 1 boundary): all `ok`. e.g. `GATE=green PR_OPEN=1 → noop` (terminal beats green), `REPORT_PRESENT=1 GATE=green → open-pr` (green beats report), `ISSUE_READY=0 PLAN_PRESENT=1 → run-implement` (loop proceeds once started). |
| The decider is testable as a subprocess driven purely by env vars — no git repos, no mocks (unlike `piv_check.test.sh`, which must build real repos) | **VERIFIED** | Spike invoked it as `env ISSUE_READY=1 … bash spike_decide.sh` and asserted the echoed token; pattern works, runs instantly. |
| A red gate must NOT silently become `noop` or fall through to `run-validate` (which would infinite-loop re-validation) | **VERIFIED** | Spike: with the explicit `red) … exit 2` branch removed, `GATE=red REPORT_PRESENT=1` would match `run-validate`. With the branch in, it exits 2 loudly. Decision below: this slice emits a loud `exit 2` boundary marker for red; the retry-ladder slice replaces it. |
| CI registers each test script explicitly (no glob/auto-discovery), so a new test must be added to `ci.yml` or it never runs | **VERIFIED** | Read `.github/workflows/ci.yml:17-23` — six `bash scripts/*.test.sh` lines, hand-listed. |
| `validate.sh` runs only `piv_check.sh`, not the unit suite — so the decider's own tests are a CI concern, not a `validate.sh` concern | **VERIFIED** | Read `.claude/validate.sh` — it execs only `piv_check.sh`. |
| Snapshot derivation from git/fs (the impure gather step) is out of scope — the decider is pure and takes the snapshot as input | **VERIFIED (by spec)** | Issue acceptance: "No side effects — does not spawn sessions, touch the worktree, push, or notify"; ADR-0023 "pure function of objective artifact state"; PRD Seam 3 assigns gathering to the (later) executor. |

**Design decision — red gate → `exit 2` (recommended) vs `noop`:** This slice is happy-path
only, but the decider must be deterministic on a red gate so it can't corrupt the loop. Two
options: (a) **`exit 2` with an "out-of-scope: retry ladder" message** — loud, forces the
next slice to consciously wire the ladder, can never masquerade as terminal; (b) `noop` —
quiet, but a red gate would look done and stall the task. **Recommended: (a).** Flag for the
reviewer in case quiet-stall is preferred.

## Patterns to Follow

Pure-state-to-verdict script shape (mirror the guard clauses + single-responsibility echo):
```bash
# SOURCE: scripts/piv_check.sh:1-15
#!/usr/bin/env bash
# Verify PIV artifact invariants for the current session's working tree.
set -euo pipefail
...
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[piv-check] not a git repo; skipping" >&2
  exit 0
fi
```

Table-driven subprocess test harness (mirror the assert helper + per-case invocation; but
drive by env vars instead of building git repos):
```bash
# SOURCE: scripts/piv_check.test.sh:1-37
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/piv_check.sh"
FAILURES=0
assert_pass() {
  local output="$1" msg="$2"
  if ! printf '%s' "$output" | grep -q "PIV checks passed"; then
    echo "FAIL: $msg (expected pass, got: $output)"
    FAILURES=$((FAILURES + 1))
  fi
}
```

Test footer / exit convention (every `*.test.sh` ends this way):
```bash
# SOURCE: scripts/piv_check.test.sh:215-221
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILURES test(s) failed."
fi
exit "$FAILURES"
```

CI registration (append one line, mirroring the existing list):
```yaml
# SOURCE: .github/workflows/ci.yml:17-23
        run: |
          bash scripts/sync.test.sh
          ...
          bash scripts/notify.test.sh
```

## Snapshot interface (the decider's input contract)
The decider reads these env vars (the closed snapshot type). Booleans are `"1"` / `"0"`.

| Var | Domain | Meaning (durable artifact it reflects) |
|-----|--------|----------------------------------------|
| `ISSUE_READY` | `1`/`0` | Issue carries the `ready` label |
| `PLAN_PRESENT` | `1`/`0` | `.agents/plans/{name}.plan.md` exists |
| `REPORT_PRESENT` | `1`/`0` | `.agents/reports/{name}-report.md` exists |
| `GATE` | `unrun`/`green`/`red` | validate gate verdict (`red` is out-of-scope this slice) |
| `PR_OPEN` | `1`/`0` | a PR is open for the branch |
| `ESCALATED` | `1`/`0` | task already escalated (terminal) |
| `ATTEMPTS` | integer | retry count — part of the type; **unused** in happy path (consumed by the retry-ladder slice) |

Output: one token on stdout from the closed set
`run-plan | run-implement | run-validate | retry-reimplement | retry-replan | escalate | open-pr | noop`
(this slice emits only `run-plan | run-implement | run-validate | open-pr | noop`).
Unset vars default to the "nothing yet" value (`0` / `unrun`).

**Precedence (verified):** terminal (`PR_OPEN` or `ESCALATED` → `noop`) → gate (`green` →
`open-pr`; `red` → `exit 2` out-of-scope) → `REPORT_PRESENT` → `run-validate` →
`PLAN_PRESENT` → `run-implement` → `ISSUE_READY` → `run-plan` → else `noop`.

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/night_shift_decide.sh` | CREATE | The pure next-action decider |
| `scripts/night_shift_decide.test.sh` | CREATE | Table-driven tests enumerating every happy-path edge + boundary |
| `.github/workflows/ci.yml` | UPDATE | Register the new test so CI runs it |

## Tasks

### Task 1: Write the pure decider
- File: `scripts/night_shift_decide.sh`
- Action: CREATE
- Implement: `#!/usr/bin/env bash` + `set -euo pipefail`. Read the seven snapshot env vars
  with safe defaults (`"${ISSUE_READY:-0}"` etc.). Apply the verified precedence chain,
  echoing exactly one token and `exit 0`. The `red` gate branch echoes an
  "OUT-OF-SCOPE: red gate → retry ladder (issue #56 is happy-path only)" message to **stderr**
  and `exit 2`. Add a top-of-file comment documenting the snapshot contract, the closed
  output set, and the ADR-0023 schedule-not-judge framing. Keep it minimal — no git/fs reads,
  no input "validation" beyond the defaults (Simplicity first).
- Mirror: `scripts/piv_check.sh:1-15` (shebang, `set -euo pipefail`, leading doc comment, stderr+exit style)
- Validate: `bash scripts/night_shift_decide.test.sh` (after Task 2) and a manual smoke:
  `ISSUE_READY=1 bash scripts/night_shift_decide.sh` → `run-plan`

### Task 2: Write the table-driven tests
- File: `scripts/night_shift_decide.test.sh`
- Action: CREATE
- Implement: Mirror the `piv_check.test.sh` skeleton (`SCRIPT_DIR`, `FAILURES`, footer,
  `exit "$FAILURES"`). Add one `check <expected> <desc> KEY=VAL …` helper that runs
  `env "$@" bash "$DECIDER"` and compares stdout to `expected`; add an
  `check_exit <code> <desc> KEY=VAL …` variant for the red-gate boundary. Enumerate every
  case from the verified spike:
  - **Happy edges:** ready+no-plan→`run-plan`; plan+no-report→`run-implement`;
    report+gate-unrun→`run-validate`; gate-green→`open-pr`; PR-open→`noop`; escalated→`noop`;
    not-ready+nothing→`noop`.
  - **Precedence stress:** PR-open beats green→`noop`; green beats report→`open-pr`;
    `ISSUE_READY=0`+plan→`run-implement` (loop proceeds once started).
  - **Boundary marker:** `GATE=red` + report → exit 2 (documents the deferred retry slice;
    the retry-ladder slice will replace this assertion).
- Mirror: `scripts/piv_check.test.sh:1-37,215-221`
- Validate: `bash scripts/night_shift_decide.test.sh` → `All tests passed.` (exit 0)

### Task 3: Register the test in CI
- File: `.github/workflows/ci.yml`
- Action: UPDATE
- Implement: Add `          bash scripts/night_shift_decide.test.sh` as the final line of the
  `run:` block, matching the existing indentation/ordering.
- Mirror: `.github/workflows/ci.yml:17-23`
- Validate: `grep -n night_shift_decide .github/workflows/ci.yml` shows the line; YAML still
  parses (block scalar unchanged in shape).

## Validation
- Unit (primary): `bash scripts/night_shift_decide.test.sh` → `All tests passed.`, exit 0.
- Regression: `bash scripts/piv_check.test.sh` and `bash scripts/notify.test.sh` still pass
  (no shared state, but cheap to confirm nothing in `scripts/` broke).
- Gate: `bash .claude/validate.sh` → `PIV checks passed.` (this branch will have the plan as
  its first commit and a report once `scripts/` changes land, satisfying `piv_check.sh`).
- CI wiring: `grep -n night_shift_decide .github/workflows/ci.yml` returns the new line.
- Manual smoke (each prints exactly the token):
  `ISSUE_READY=1 bash scripts/night_shift_decide.sh` → `run-plan`;
  `PLAN_PRESENT=1 REPORT_PRESENT=1 GATE=green bash scripts/night_shift_decide.sh` → `open-pr`.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors (`night_shift_decide.test.sh` → `All tests passed.`)
- [ ] Follows existing patterns (`piv_check.sh` script shape, `piv_check.test.sh` harness)
- [ ] Pure: decider reads no git/fs, spawns no session, pushes/notifies nothing (snapshot is input)
- [ ] Decision derived purely from the durable-artifact snapshot — never from agent memory
- [ ] Same snapshot always yields the same decision (idempotent / restartable)
- [ ] Table-driven tests enumerate every happy-path edge + precedence-stress + red-gate boundary
- [ ] Closed output set documented in-file; only happy-path members emitted this slice
- [ ] CI runs the new test (`ci.yml` updated)
