# Report: Deny untrusted fetch-and-execute; migrate denies to exit(2)

**Plan**: `.agents/plans/security-guard-remote-exec-exit2.plan.md`
**Issue**: #28
**Branch**: `feat/28-security-guard-remote-exec-exit2`

## Tasks completed
- ✅ **Task 1** — Added `REMOTE_EXEC_PATTERNS` + `check_remote_exec` (Bash-only, mirrors
  `check_recursive_delete`). Patterns exactly the probe-verified set: pipe-to-shell
  (`\b` avoids `| shasum`), `sh -c "$(…)"` / backtick, and `eval "$(…)"` / backtick.
- ✅ **Task 2** — Wired `check_remote_exec` into the `reason` chain after
  `check_env_file` / `check_recursive_delete`.
- ✅ **Task 3** — Migrated deny emission to `print(reason, file=sys.stderr); sys.exit(2)`.
  Removed the `json.dumps({permissionDecision: deny})` shape. Parse-error path stays at
  `exit(0)` (fail open); `json` import retained for `json.load`. Docstring updated to list
  the remote-exec denial and the exit(2)/stderr contract (ADR-0016 rationale).
- ✅ **Task 4** — Created `scripts/security_guard.test.sh` driving the stdin → exit-code +
  stderr contract for deny / deny-preserved / allow / fail-open cases.
- ✅ **Task 5** — Added `bash scripts/security_guard.test.sh` to `.github/workflows/ci.yml`
  alongside the other hook tests.

## Validation results
| Check | Result |
|-------|--------|
| `ast.parse` on security_guard.py | OK |
| `bash scripts/security_guard.test.sh` | All tests passed (exit 0) |
| `bash scripts/validate_gate.test.sh` (sibling regression) | All tests passed |
| `yaml.safe_load` on ci.yml | OK |
| Spot-check `curl x \| sh` | reason on stderr, `rc=2` |
| Spot-check `cat s \| shasum` | no output, `rc=0` |
| Spot-check `not json` | fail open, `rc=0` |

## Files changed
- `.claude/hooks/security_guard.py` — UPDATE (patterns, check fn, deny path, docstring)
- `scripts/security_guard.test.sh` — CREATE (12 assertions across deny/allow/fail-open)
- `.github/workflows/ci.yml` — UPDATE (one line)

## Deviations from plan
- **`run_hook` needed a `set +e`/`set -e` guard.** The plan's helper
  (`STDERR="$(… python3 "$HOOK" …)"; RC=$?`) aborts under `set -euo pipefail`: an intended
  `exit(2)` deny makes the command-substitution assignment fail and trips `set -e` before
  `RC=$?` runs. Wrapped the capture in `set +e` … `set -e` so deny cases are recorded
  instead of aborting the suite. (The sibling `validate_gate.test.sh` never hit this because
  its hook always exits 0.) No change to the asserted contract.

## Tests written
`scripts/security_guard.test.sh` — assertion helpers `assert_deny` (RC=2 + non-empty
stderr), `assert_allow` (RC=0 + empty stderr), `assert_fail_open` (RC=0). Cases: 5
remote-exec denies, 2 preserved denies (`.env`, `rm -rf`), 3 allows
(`curl -o`, `| shasum`, `.env.example`), 1 malformed-stdin fail-open.
