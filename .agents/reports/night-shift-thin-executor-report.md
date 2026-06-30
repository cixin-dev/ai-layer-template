# Implementation Report: night-shift-thin-executor

Issue #61 — the Night Shift **thin executor**: snapshot → decide → dispatch, driving one
`ready` Issue through `/plan` → `/implement` → `/validate` with no human between phases.

## Tasks Completed

### Task 1: ADR-0024 (runtime substrate) ✅
- `docs/adr/0024-night-shift-executor-substrate-headless-claude-own-clone.md` — mirrors ADR-0023
  format (Status / Context / Decision / Why-over-alternatives / Consequences).
- Records: (1) phase sessions = headless `claude -p "/<phase>"` subprocesses (structural
  fresh-session isolation); (2) executor runs in a dedicated Night Shift clone (resolves the HEAD
  race, CLAUDE.md); (3) recurring scheduler deferred to #63. Auth posture: claude.ai subscription,
  host must not export `ANTHROPIC_API_KEY`. Rejects cron / `/loop`+`/routines` / Workflow subagents
  / shared checkout. English (canonical doc).

### Task 3: Snapshot gatherer (TDD) ✅
- `gather_snapshot` + `resolve_slug` + `_artifact_root` + `worktree_path`.
- Maps durable artifacts → the six decider env vars. **Faithfulness verified** (A6/A7):
  report-present + plan-not-archived ⇒ `GATE=unrun`; plan in `completed/` ⇒ `GATE=green`. The
  executor never derives GATE from `.claude/validate.sh` (which `piv_check.sh` greens once
  plan+report exist, *before* `/validate` archives) — only `completed/` presence = validate-passed.
- `resolve_slug`: branch-authoritative post-implement, draft-marker fallback pre-implement (A1/A2/A3).
- Worktree root switch verified (A9): artifacts read from the worktree once it exists, else ROOT.

### Task 4: Decision dispatch (TDD) ✅
- `dispatch` + `claude_run` + `_plan_path_in`. Each decision → the correct slash command in the
  correct cwd: `/plan`·`/implement` in the clone root (B1/B2), `/validate`·open-pr in the worktree
  (B3/B4). `set-phase` recorded per phase (loop_state). **Delegation verified** (B5): dispatch
  performs **no** gh of its own — no push, no `pr create`, no notify (all owned by `/validate`
  Phase 5).

### Task 5: Drive loop + claim gate + CI wiring (TDD) ✅
- `run`: selection guard → claim → bounded decide/dispatch loop → release on terminal.
- Claim gate (C1): skips an already-`in-progress` Issue (never double-grab). Not-ready skip (C2).
- **Full happy-path drive (C3): every action comes from the decider** — `run-plan`→`run-implement`
  →`run-validate`→`noop`, exactly 3 fresh phase sessions in PIV order, `in-progress` claimed
  **before** any dispatch, released on terminal, zero `pr create` by the executor. Proves the
  executor carries **no loop logic**.
- Terminal no-op (C4): PR already open ⇒ `noop` ⇒ release, no dispatch. MAX_ITERS (C5): runaway
  stops at the cap (exit 3).
- `.github/workflows/ci.yml`: `night_shift_run.test.sh` added alongside the other `*.test.sh`.

### Task 2 & Task 6: live Seam-3 probes ⏸️ PENDING OPERATOR (see Go/No-Go)
- These spawn real `claude -p` PIV sessions (subscription credit), open a **real GitHub PR**, and
  need a throwaway `ready` Issue in a **dedicated Night Shift clone** under the graduated push
  posture. They are outward-facing and were **not** run autonomously — handed to the operator.
- The phase-spawning **primitive** is already VERIFIED from planning (`probe-echo` →
  `PROBE_SLASHCMD_OK`, exit 0, on the subscription); what remains is the real-command end-to-end run.

## Validation Results
- `bash scripts/night_shift_run.test.sh` → **All tests passed** (56 assertions, cases A1–A9, B1–B5,
  C1–C5).
- `bash scripts/night_shift_decide.test.sh` → All tests passed (regression — decider untouched).
- `bash scripts/loop_state.test.sh` → All tests passed (regression — state store untouched).
- `bash -n scripts/night_shift_run.sh` → syntax OK. (shellcheck not installed on host.)
- `bash .claude/validate.sh` → green (plan is first commit; report present).
- Offline end-to-end smoke (fakes): claim → `/plan`→`/implement`→`/validate` (3 sessions) →
  PR-open ⇒ `noop` ⇒ release; final recorded phase `validate`. Timeline inspected — non-vacuous.

## Files Changed
| File | Action |
|------|--------|
| `docs/adr/0024-night-shift-executor-substrate-headless-claude-own-clone.md` | Created |
| `scripts/night_shift_run.sh` | Created (the thin executor, 263 LOC) |
| `scripts/night_shift_run.test.sh` | Created (56 assertions, externals injected) |
| `.github/workflows/ci.yml` | Updated (+`night_shift_run.test.sh`) |
| `.agents/plans/night-shift-thin-executor.plan.md` | Seeded as branch first commit |
| `.agents/reports/night-shift-thin-executor-report.md` | This report |

## Tests Written
`night_shift_run.test.sh` — all externals (claude, gh, git state) dependency-injected; zero credit
spend. Mirrors `loop_state.test.sh` (harness), `notify.test.sh` (logging fakes),
`night_shift_decide.test.sh` (decider invocation). A stateful fake `claude` simulates each phase's
durable-artifact effect so the snapshot advances the decider; a stateful fake `gh` reflects
claim/PR state via markers; a shared TIMELINE log proves ordering (claim-before-dispatch).

## Deviations from Plan
| Deviation | Rationale |
|-----------|-----------|
| `dispatch` resolves the validate/open-pr cwd via `_artifact_root` (worktree-if-exists-else-ROOT), the **same** resolution `gather_snapshot` uses — not a bare `worktree_path`. | Unifies dispatch and snapshot on one working-dir rule and lets the full-drive unit test (C3) prove "no loop logic" offline without spinning a real worktree (B3 still verifies the real-worktree cwd; Task 6 covers it live). Behavior is identical when a worktree exists. |
| `resolve_slug` / `worktree_path` git pipelines carry `\|\| true`. | `set -euo pipefail` + a non-git ROOT makes `git` exit 128, which pipefail would treat as fatal. An unresolved slug / absent worktree is a normal state, not an error. |
| Tasks 2 & 6 (live probes) handed to the operator rather than run in this session. | They consume subscription credit (nested `claude -p`), open a real PR, and need a throwaway `ready` Issue + the dedicated Night Shift clone + graduated push posture. Outward-facing + hard-to-reverse ⇒ explicit authorization required. Deterministic code is fully unit-verified independently. |

## Go/No-Go
🟡 **Unit GREEN; end-to-end PENDING.** All deterministic seams are verified offline and regressions
are green — the executor is structurally complete and the substrate is recorded (ADR-0024). The
plan's acceptance criterion "end-to-end behavior verified (Task 6 probe)" is **not yet met**: the
live Seam-3 probes must run on the operator's dedicated Night Shift clone (subscription auth, no
`ANTHROPIC_API_KEY`, graduated push) against a throwaway `ready` Issue, observing 3 distinct
`claude -p` processes, a worktree at `../<repo>-feat/61-<slug>`, plan seeded as first commit, branch
pushed, PR opened (never merged), `pr-ready` notify fired, `in-progress` removed on terminal. Record
those results here before declaring #61 done.
