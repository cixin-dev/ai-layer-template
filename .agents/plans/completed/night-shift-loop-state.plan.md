# Plan: Night Shift — durable per-task loop state (attempts + phase)

## Summary
Build the durable per-task loop-state store the Night Shift decider reads: current
**phase** and **attempts so far**, persisted so they survive a process crash/restart. The
store is a small bash script `scripts/loop_state.sh` that reads/writes a per-task
`key=value` file under a gitignored `.night-shift/<task>.state` dir — mirroring
`scripts/piv_check.sh` (a script that reads fs/git state) and the `notify.sh`
positional-arg + env-override idiom. The decider's only contract is *read "attempts so far"
and "current phase" for a given task*; the medium is an implementation detail behind that
contract. Substrate decision (local file vs. GitHub Issue vs. git notes) was the issue's
HITL `/plan` call — **resolved to local state file**; rationale + rejected alternatives are
recorded below (per the issue's "ADR or plan rationale" criterion, chosen: plan rationale,
no ADR, so the PR carries no canonical-doc edit). This slice tests the **store in
isolation** (write → restart → read back); the decider+state idempotency test lands later in
the retry-ladder slice (#60).

## User Story
As a maintainer, I want the retry count and current phase stored as durable per-task state,
so that the loop resumes correctly after a crash or restart (PRD User Story 24).

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW |
| Complexity | LOW |
| Systems affected | `scripts/` (new store + test), `.github/workflows/ci.yml`, `.gitignore` |
| Issue | #57 |

## Substrate Decision (records the issue's HITL `/plan` choice)
**Chosen: a local per-task `key=value` state file** (`.night-shift/<task>.state`, gitignored),
read/written by `scripts/loop_state.sh`. Recorded here as **plan rationale** (not an ADR), by
explicit choice, so this slice's PR touches no canonical doc (no `## 變更說明` required).

- **Why a file.** v1 is serial, single-repo, single-machine; the hard requirement is
  *process-restart* survival, which a file fully satisfies (probe-verified below). It mirrors
  the codebase grain exactly (`piv_check.sh` reads fs state; this writes it), gives zero-mock
  unit tests via a `NIGHT_SHIFT_STATE_DIR` temp-dir override, and keeps the **pure** decider's
  critical path off the network (ADR-0023: the decider is a pure function of objective state).
- **Auditability** (the issue asked to weigh it) is delivered by `/dashboard` (#64, reads this
  store) plus the genuine PIV audit trail (plan, report, PR, git log). The store only adds the
  one fact those artifacts *cannot* encode — the **attempt count**. So losing git-history
  visibility of the counter costs little.
- **Rejected — GitHub Issue:** maximal auditability but `gh` network I/O on the loop's hot
  path, isolation tests need a `gh` shim, rate-limit/latency/parse-fragility, comment churn on
  every retry.
- **Rejected — git notes:** git-native but fragile (clobber-on-fetch, custom refspec, merge
  friction) and heavier to test — dominated by the file on simplicity and by the Issue on
  auditability.

**Design note — what is durable vs. derived.** Per ADR-0023 the decider derives *which phase
runs next* from objective artifacts (plan present? report? gate verdict?). Of the two fields
this store exposes, **`attempts` is the load-bearing, non-derivable datum** (no PIV artifact
records "we re-implemented twice"); **`phase` is a recorded label** for observability/resume.
Artifacts stay authoritative for what exists; the store is authoritative for the attempt count.

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| A per-task `key=value` file survives a process restart — a value written by one invocation is read back intact by a separate invocation (= restart). | **VERIFIED** | Throwaway spike: process 1 ran `set-phase issue-57 implement` + `incr-attempts` ×2 → file `phase=implement / attempts=2`; a *separate* `bash` invocation (process 2 = restart) read back `phase=implement`, `attempts=2`. Unknown task → `phase=''`, `attempts=0`. |
| Each `loop_state.sh` call is its own process, so every `get-*` is structurally a post-restart read — restart-survival needs no special harness, just separate invocations. | **VERIFIED** | Same spike: writes and reads were distinct `bash loop_state_spike.sh …` calls; reads returned what prior calls wrote. |
| Reading the same unchanged state twice yields the same values (idempotent reads → "same state → same decision" upstream). | **VERIFIED** | Spike reads are pure `grep`/`cut` over the file; no mutation on read. Covered again by test (h). |
| The new test is only gated if explicitly listed in `ci.yml` (the job names each test; there is no glob runner). | **VERIFIED** | `.github/workflows/ci.yml` lists each `bash scripts/*.test.sh` by name; `validate.sh` runs only `piv_check.sh`. → Task 3 adds the new test to that list. |
| `<task>` ids passed by callers (Issue number e.g. `57`, or kebab slug) are filesystem-safe. | **ASSUMED** | v1 callers pass issue numbers / kebab slugs. Mitigation: store treats `<task>` as a token and namespaces by it; a `/`-bearing id would mis-path. First Implement step keeps ids simple; optional one-line sanitize noted in Task 1 if trivially cheap. Low risk in serial v1. |

## Patterns to Follow

**Script header + read-guard idiom** (state script, fail-open reads):
```bash
#!/usr/bin/env bash
set -euo pipefail
# ... guard reads so a missing file/key never errors:
value=$(grep -E "^key=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true)
```
`// SOURCE: scripts/piv_check.sh:1-3,63-70` (the `… 2>/dev/null … || true` capture-then-test idiom)

**Positional args + env-override for testability:**
```bash
level="${1:-info}"          # positional subcommand/args
# env override with a sane default, exactly how the bell target is overridden:
{ printf '\a' > "${NOTIFY_BELL_TARGET:-/dev/tty}"; } 2>/dev/null || true
```
`// SOURCE: .claude/hooks/notify.sh:20-32` → mirror as `${NIGHT_SHIFT_STATE_DIR:-.night-shift}`

**Test harness** (env-override target + mktemp + trap + assert helpers + FAILURES counter):
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d /tmp/loopstatetest.XXXXXX)"; trap 'rm -rf "$WORK"' EXIT
FAILURES=0
export NIGHT_SHIFT_STATE_DIR="$WORK/state"   # like notify.test.sh exporting NOTIFY_BELL_TARGET
assert_eq() { [ "$1" = "$2" ] || { echo "FAIL: $3 (want '$2' got '$1')"; FAILURES=$((FAILURES+1)); }; }
# ... end:
[ "$FAILURES" -eq 0 ] && echo "All tests passed." || echo "$FAILURES test(s) failed."; exit "$FAILURES"
```
`// SOURCE: scripts/notify.test.sh:4-13,28-37` + `scripts/piv_check.test.sh:10-37,215-220`

**CI test list** (each test named explicitly):
```yaml
      - name: Run tests
        run: |
          bash scripts/sync.test.sh
          ...
          bash scripts/notify.test.sh
```
`// SOURCE: .github/workflows/ci.yml` (the `run:` block) — append `bash scripts/loop_state.test.sh`

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/loop_state.sh` | CREATE | The durable store: `get-phase / get-attempts / set-phase / incr-attempts` over `.night-shift/<task>.state`. |
| `scripts/loop_state.test.sh` | CREATE | Table-driven store tests: default reads, write→read, increment, restart-survival, namespacing, corrupt-value fallback, idempotent read. |
| `.github/workflows/ci.yml` | UPDATE | Add `bash scripts/loop_state.test.sh` to the test job so the store is gated. |
| `.gitignore` | UPDATE | Add `.night-shift/` so the runtime state dir is never committed. |

## Tasks
Ordered, atomic, each independently verifiable. Work test-informed (tdd-gate): write the
store's contract and tests, implement to green, never leave the suite red.

### Task 1: Create the store `scripts/loop_state.sh`
- File: `scripts/loop_state.sh`
- Action: CREATE (`chmod +x`)
- Implement: a positional-subcommand bash script. Interface (the decider/executor contract):
  - `loop_state.sh get-phase <task>`     → prints recorded phase, empty if unset
  - `loop_state.sh get-attempts <task>`  → prints attempt count, `0` if unset/corrupt
  - `loop_state.sh set-phase <task> <phase>`  → records phase (preserves attempts)
  - `loop_state.sh incr-attempts <task>` → increments, persists, prints new count
  - unknown/missing subcommand or task → usage on stderr, `exit 2`
  Details:
  - `set -euo pipefail`; state dir = `${NIGHT_SHIFT_STATE_DIR:-.night-shift}`; file =
    `$dir/<task>.state`; format two lines `phase=…` / `attempts=…`.
  - Reads fail-open: missing file/key → empty (phase) or `0` (attempts); guard with
    `2>/dev/null … || true` (mirror `piv_check.sh:63-70`).
  - `get-attempts` validates numeric (`grep -E '^[0-9]+$'`), falls back to `0` on corruption.
  - Writes are **atomic** (write to `mktemp`, `mv` into place) and update one key without
    clobbering the other (`grep -v "^key=" old; echo "key=val"`), `mkdir -p` the dir first —
    so a crash mid-write can't leave a half-file (matters for "survive a crash").
  - Keep `<task>` as an opaque token (namespacing); do not over-engineer sanitization.
- Mirror: `scripts/piv_check.sh:1-3,63-70`, `.claude/hooks/notify.sh:20-32`
- Validate: `bash -n scripts/loop_state.sh` (syntax); manual smoke:
  `NIGHT_SHIFT_STATE_DIR=$(mktemp -d) bash scripts/loop_state.sh get-attempts 57` → `0`.

### Task 2: Create the test suite `scripts/loop_state.test.sh`
- File: `scripts/loop_state.test.sh`
- Action: CREATE
- Implement: harness per `notify.test.sh`/`piv_check.test.sh` (mktemp `WORK`, `trap` cleanup,
  `export NIGHT_SHIFT_STATE_DIR="$WORK/state"`, `FAILURES` counter, `assert_eq` helper, final
  pass/fail line + `exit "$FAILURES"`). Cases (each maps to an acceptance criterion):
  - (a) `get-attempts` unknown task → `0` (default, no file).
  - (b) `get-phase` unknown task → empty.
  - (c) `set-phase` then `get-phase` → returns the phase (**write → read**).
  - (d) `incr-attempts` from nothing → `1`; again → `2` (**write → read**, increments).
  - (e) **restart-survival**: after `set-phase`+`incr-attempts`, a *fresh* invocation reads
    back the same phase and attempts (separate `bash` calls = restart).
  - (f) **namespacing**: task A's attempts/phase do not affect task B.
  - (g) **corrupt value**: write `attempts=oops` into the file directly → `get-attempts` → `0`.
  - (h) **idempotent read**: two consecutive `get-attempts` on unchanged state → identical.
  - (i) **non-clobber**: `set-phase` after `incr-attempts` keeps attempts; `incr-attempts`
    after `set-phase` keeps phase.
- Mirror: `scripts/notify.test.sh:4-46`, `scripts/piv_check.test.sh:12-48`
- Validate: `bash scripts/loop_state.test.sh` → `All tests passed.` (exit 0). Iterate Task 1
  until green.

### Task 3: Gate the store in CI
- File: `.github/workflows/ci.yml`
- Action: UPDATE
- Implement: append `          bash scripts/loop_state.test.sh` to the `test` job's `run:`
  block, after `bash scripts/notify.test.sh`.
- Mirror: `.github/workflows/ci.yml` (existing `run:` list)
- Validate: `grep -q 'loop_state.test.sh' .github/workflows/ci.yml`; optionally re-run the
  whole list locally (Validation section).

### Task 4: Ignore the runtime state dir
- File: `.gitignore`
- Action: UPDATE
- Implement: add a line `.night-shift/` (the gitignored per-task state dir).
- Mirror: `.gitignore` (existing `notify.local.conf` runtime-artifact entry)
- Validate: create `.night-shift/x.state`, run `git status --porcelain` → it is **not** listed;
  then remove the probe file.

## Validation
- **Store unit suite (primary):** `bash scripts/loop_state.test.sh` → `All tests passed.`
- **Syntax:** `bash -n scripts/loop_state.sh scripts/loop_state.test.sh`
- **Full local CI mirror** (the exact gate that runs on PR):
  ```
  bash scripts/sync.test.sh && bash scripts/unsync.test.sh && \
  bash scripts/validate_gate.test.sh && bash scripts/security_guard.test.sh && \
  bash scripts/piv_check.test.sh && bash scripts/notify.test.sh && \
  bash scripts/loop_state.test.sh
  ```
- **PIV gate (session-end Stop hook):** `bash .claude/validate.sh` → `PIV checks passed.`
  (unchanged; the new test is gated by CI, not by `validate.sh`, matching every sibling test).
- **Gitignore check:** `mkdir -p .night-shift && touch .night-shift/probe.state && git status
  --porcelain | grep -q night-shift && echo LEAKED || echo IGNORED; rm -rf .night-shift`
  → `IGNORED`.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors (`loop_state.test.sh` green; full CI mirror green)
- [ ] Follows existing patterns (`piv_check.sh` script shape, `notify.test.sh` harness, CI test list)
- [ ] Every external-behavior claim is VERIFIED by a probe, or carried as an explicit risk
- [ ] End-to-end behavior verified — issue #57 criteria:
  - [ ] A storage substrate is chosen and the decision recorded (plan rationale above)
  - [ ] State exposes "current phase" and "attempts so far" for a given task
  - [ ] State survives a process restart — re-reading after a restart yields the same values
  - [ ] Store-level tests cover read / write / restart-survival
  - [ ] Loop progress is recorded only in this store — no progress lives in agent memory
