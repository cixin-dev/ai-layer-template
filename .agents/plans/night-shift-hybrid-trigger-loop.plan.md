# Plan: Night Shift hybrid trigger — event-driven drain + ~5-min safety-net poll (serial v1)

## Summary
Build the **outer loop** that feeds the already-built per-task executor
(`scripts/night_shift_run.sh`, #61). A new `scripts/night_shift_loop.sh` repeatedly
**selects** the next grabbable `ready-for-agent` Issue and hands it to the executor, draining
the ready set **back-to-back with no idle wait** (the event-driven happy path), and **sleeping
~5 min only when the set is empty** (the safety-net poll that re-discovers newly-ready Issues
and reconciles any state the synchronous path missed). Serial (concurrency dial defaults to 1),
with a file + signal **kill switch**. Because the executor already claims (`in-progress`) before
dispatch, chains phases internally, and leaves every finished Issue non-grabbable (PR open on
success, or still-claimed on failure), the loop is a thin, level-triggered selection wrapper — it
holds no phase logic. This slice also **settles and records** the trigger-label collision: the
Night Shift trigger **is** the existing `ready-for-agent` label (no separate `ready` label), and
reconciles the stale `ready` references in code/docs.

## User Story
As an operator, I want a loop that drains my `ready-for-agent` Issue queue one task at a time —
starting the next task the instant the previous one opens its PR, and polling every ~5 min for new
work — so that a night's queue turns itself into a stack of review-ready PRs with no human between
phases, and I can stop it at any time.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW |
| Complexity | MEDIUM |
| Systems affected | `scripts/` (new loop + tests), `.github/workflows/ci.yml`, `docs/adr/`, `CONTEXT.md`, `.agents/prds/piv-ralph-loop.prd.md`, `.agents/reports/` (operator runbook) |
| Issue | #63 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| The trigger label is the existing `ready-for-agent`; no separate `ready` label exists or is needed | **VERIFIED (decision)** | `gh label list` → `ready-for-agent` + `in-progress` exist, **no `ready`**. Executor already defaults `NIGHT_SHIFT_TRIGGER_LABEL=ready-for-agent` (`night_shift_run.sh:37`). Operator confirmed "Same — reuse ready-for-agent." Recorded in ADR-0025 (Task 5). |
| The selection query returns `number<TAB>csv-labels` for open ready Issues | **VERIFIED** | `gh issue list --label ready-for-agent --state open --json number,labels --jq '.[] \| [.number, ([.labels[].name] \| join(","))] \| @tsv'` → exit 0, output `64\tready-for-agent` / `63\t…` / `62\t…`. |
| Each `scripts/*.test.sh` is run by name in CI (not auto-discovered) | **VERIFIED** | `.github/workflows/ci.yml` lists each test file explicitly → the new `night_shift_loop.test.sh` MUST be added there (Task 4). |
| **Terminal-exclusion invariant:** after `night_shift_run.sh <N>` returns, #N is no longer grabbable, so `drain` always terminates (no hot-spin, no starvation) | **VERIFIED (by reading the executor)** | `run()` returns 0 **only** on `noop`; `noop` requires `PR_OPEN=1` **or** `ESCALATED=1` (`night_shift_decide.sh:34`); on `noop` it releases the claim (`night_shift_run.sh:253`). So after rc 0 the Issue is either **PR-open** (success) or **escalated** (durable marker, claim released, no PR) — both excluded by `select`'s terminal filter. The only non-zero return is the runaway cap (`night_shift_run.sh:267`, rc 3), which never releases → Issue keeps `in-progress` → excluded by the claim filter. Either way #N leaves the grabbable set. |
| `night_shift_run.sh snapshot <N>` is a safe read-only seam that prints a real `PR_OPEN=` and `ESCALATED=` | **VERIFIED** | `gather_snapshot` reads `escalated` via `loop_state.sh get-escalated` and prints both `PR_OPEN` and `ESCALATED` (`night_shift_run.sh:106,128-129`). The loop reuses this seam for the terminal check rather than re-implementing branch/PR resolution. |
| **#62 (retry ladder + escalation) is now MERGED** (this changes the earlier draft assumption) | **VERIFIED** | As of PR #80 (commit `c2c6d3d`, on `origin/main` and the local checkout) `run()`'s case handles `retry-reimplement\|retry-replan\|escalate` (`night_shift_run.sh:257`); `escalate` sets a **durable** marker (`:188`), reaches `noop` next iteration, and **releases the claim** (`:253`). So an escalated Issue is `ready-for-agent` + not-`in-progress` + no-PR — which makes `select`'s `ESCALATED=1` terminal-check **load-bearing** (without it the loop would hot-spin on escalated Issues). The loop still treats the runaway-cap non-zero rc as "left claimed; continue" (quiescence on a genuinely stuck task). The loop fires **no** notifications of its own — `escalate`/`pr-ready` stay owned by the executor + `/validate` (Seam-4). |
| A live full `drain`/`loop` cannot be a validation step | **ASSUMED (by design)** | It would spawn real `claude -p` phase sessions (spends credits, mutates GitHub). Validation uses the offline unit tests + a **read-only** live `select` probe (Task 7). Running the real loop is the operator's action, not the gate's. |

## Patterns to Follow

**1. DI vars + subcommand routing (mirror the executor exactly).**
```bash
# SOURCE: scripts/night_shift_run.sh:31-47
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GH="${NIGHT_SHIFT_GH:-gh}"
ROOT="${NIGHT_SHIFT_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}"
TRIGGER_LABEL="${NIGHT_SHIFT_TRIGGER_LABEL:-ready-for-agent}"
CLAIM_LABEL="${NIGHT_SHIFT_CLAIM_LABEL:-in-progress}"
export NIGHT_SHIFT_STATE_DIR="${NIGHT_SHIFT_STATE_DIR:-$ROOT/.night-shift}"
# SOURCE: scripts/night_shift_run.sh:271-295  (case-based main; usage on bad arg)
```

**2. gh helper with `|| true` so a non-zero gh never trips `set -e`.**
```bash
# SOURCE: scripts/night_shift_run.sh:56-60
_pr_open() { local out; out="$("$GH" pr list --head "$1" --state open --json number 2>/dev/null || true)"; [ -n "$out" ] && [ "$out" != "[]" ]; }
```

**3. Test harness: assert helpers + `$BIN` fakes injected via env, logged to `TIMELINE` for ordering.**
```bash
# SOURCE: scripts/night_shift_run.test.sh:19-40 (assert_eq/contains/not_contains)
# SOURCE: scripts/night_shift_run.test.sh:60-89 (fake gh: logs "$*" to GH_LOG/TIMELINE; case on "$1 $2")
# SOURCE: scripts/night_shift_run.test.sh:55-89 (stateful fakes via a $SIM dir: markers flip issue-view/pr-list output)
```

**4. ADR format (H1 = title, no number prefix; number is in the filename).**
```markdown
# <decision title>
**Status:** Accepted (2026-07-01); relates to the Night Shift PRD and #63.
## Context
## Decision
## Why this over the alternatives
## Consequences
# SOURCE: docs/adr/0023-night-shift-triggers-schedule-not-judge.md:1-79
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/night_shift_loop.sh` | CREATE | The outer loop: `select` / `drain` / `loop` subcommands + kill switch + concurrency dial |
| `scripts/night_shift_loop.test.sh` | CREATE | Offline unit tests (fakes for `gh` and the executor `$RUN`); mirrors `night_shift_run.test.sh` |
| `.github/workflows/ci.yml` | UPDATE | Add `bash scripts/night_shift_loop.test.sh` to the test job |
| `docs/adr/0025-night-shift-trigger-label-is-ready-for-agent.md` | CREATE | Record the label decision (same label, not distinct) |
| `scripts/night_shift_decide.sh` | UPDATE | Comment: `ready` → `ready-for-agent` (`ISSUE_READY` line) |
| `scripts/night_shift_run.sh` | UPDATE | Header + `TRIGGER_LABEL` comment: `ready` → `ready-for-agent`; resolve "(#63 renames)" note |
| `CONTEXT.md` | UPDATE | Night Shift / Day Shift defs name the real `ready-for-agent` label (ADR-0025 ref) |
| `.agents/prds/piv-ralph-loop.prd.md` | UPDATE | Replace the "Trigger-label name is unsettled" bullet with the decision |
| `.agents/reports/night-shift-loop-runbook.md` | CREATE | Standalone operator runbook: start (persistent/cron), kill switch, observe, teardown |

## Tasks
Ordered TDD slices — write the test slice, then the implementation, run
`bash scripts/night_shift_loop.test.sh` after each, fix before moving on.

### Task 1: `select` — the selection policy (the pure, testable seam)
- File: `scripts/night_shift_loop.sh` (CREATE), `scripts/night_shift_loop.test.sh` (CREATE)
- Action: CREATE
- Implement:
  - Header block (usage/DI docstring) + DI vars per Pattern 1, plus:
    `RUN="${NIGHT_SHIFT_RUN:-$SCRIPT_DIR/night_shift_run.sh}"`,
    `POLL_INTERVAL="${NIGHT_SHIFT_POLL_INTERVAL:-300}"`,
    `SLEEP="${NIGHT_SHIFT_SLEEP:-sleep}"`,
    `STOP_FILE="${NIGHT_SHIFT_STOP_FILE:-$NIGHT_SHIFT_STATE_DIR/stop}"`,
    `CONCURRENCY="${NIGHT_SHIFT_CONCURRENCY:-1}"`,
    `MAX_POLLS="${NIGHT_SHIFT_MAX_POLLS:-}"` (empty = unbounded; tests bound it).
  - `_candidates_tsv()` → runs the VERIFIED query (Pattern 2 guard style):
    `"$GH" issue list --label "$TRIGGER_LABEL" --state open --json number,labels --jq '.[] | [.number, ([.labels[].name] | join(","))] | @tsv' 2>/dev/null || true`
  - `_terminal_for()` → `"$RUN" snapshot "$1" 2>/dev/null | grep -qE '^(PR_OPEN|ESCALATED)=1$'`
    (exit 0 = already terminal; reuses the executor's read-only seam, not a re-implementation).
  - `select_issue()` → read TSV sorted ascending, skip claimed (CSV-token match
    `case ",$labels," in *",$CLAIM_LABEL,"*) continue ;; esac`), skip terminal, print the first
    (lowest-numbered) survivor and `return 0`; print nothing if none. Use a `while IFS=$'\t' read`
    over **process substitution** `< <(_candidates_tsv | sort -n)` so `return` exits the function
    (a `cmd | while` subshell would swallow it).
  - `main()`: `case "$1" in select) select_issue ;; …; ''|-h|--help) usage ;; *) usage; exit 2 ;; esac`
- Test slice S (fakes: `gh issue list` emits controllable TSV; `$RUN snapshot N` emits `PR_OPEN=`/`ESCALATED=`):
  - S1 lowest-numbered ready wins (`63,62` both fresh → `62`).
  - S2 `in-progress` candidate skipped.
  - S3 terminal skipped: `PR_OPEN=1` → excluded; and `ESCALATED=1` → excluded.
  - S4 empty ready set → empty output.
- Mirror: `scripts/night_shift_run.sh:53-60,271-295`; `scripts/night_shift_run.test.sh:19-121`
- Validate: `bash scripts/night_shift_loop.test.sh`

### Task 2: `drain` — event-driven back-to-back dispatch (no idle wait)
- File: `scripts/night_shift_loop.sh`, `scripts/night_shift_loop.test.sh`
- Action: UPDATE
- Implement:
  - `_require_serial()` → `[ "$CONCURRENCY" = "1" ] || { echo "night_shift_loop: serial only in v1 (concurrency=$CONCURRENCY reserved for a later graduation)" >&2; return 2; }`
  - `_stopped()` → `[ -f "$STOP_FILE" ]`
  - `drain()`: `_require_serial || return $?`; then `while :`: if `_stopped`, print
    `"kill switch: $STOP_FILE present — stopping"` and `return 0`; `n="$(select_issue)"`;
    `[ -n "$n" ] || return 0` (ready set empty → done); `echo "dispatch: #$n"`;
    `rc=0; "$RUN" "$n" || rc=$?`; if `rc != 0` echo `"executor rc=$rc for #$n — task left claimed; continuing" >&2`;
    loop again immediately (**no sleep** — this is the event-driven property).
  - Route `drain` in `main`.
- Test slice D (stateful fake `$RUN`: `run N` marks #N terminal-or-claimed; `snapshot N` reflects it; fake `gh issue list` reflects claim markers):
  - D1 two ready Issues drained in ascending order (`62` then `63`), each dropping out after its
    run; `drain` returns 0; the fake `SLEEP` is **never** invoked (assert via TIMELINE / a sleep log).
  - D2 executor failure (`$RUN` returns 4 and leaves #N claimed) → `drain` returns 0, dispatched
    once, stderr contains `executor rc=4`, and #N is excluded on the next pass (no re-dispatch).
- Mirror: `scripts/night_shift_run.sh:223-267` (bounded drive loop shape); `scripts/night_shift_run.test.sh:374+` (Slice C — drive/claim/selection)
- Validate: `bash scripts/night_shift_loop.test.sh`

### Task 3: `loop` — the persistent poll + kill switch (default entry point)
- File: `scripts/night_shift_loop.sh`, `scripts/night_shift_loop.test.sh`
- Action: UPDATE
- Implement:
  - `loop()`: `_require_serial || return $?`; `trap 'echo "signal received — stopping loop"; exit 0' INT TERM`;
    `polls=0`; `while :`: if `_stopped` print `"kill switch … stopping loop"` and `return 0`;
    `drain`; `polls=$((polls+1))`; if `[ -n "$MAX_POLLS" ] && [ "$polls" -ge "$MAX_POLLS" ]` print
    `"reached MAX_POLLS=$MAX_POLLS — exiting"` and `return 0`; else
    `echo "idle: sleeping ${POLL_INTERVAL}s before next poll"; "$SLEEP" "$POLL_INTERVAL"`.
  - `main`: bare/no-arg invocation → `loop` (primary entry); also route explicit `loop`.
- Test slice L (fake `SLEEP` records calls; `MAX_POLLS` bounds the run):
  - L1 empty ready set → loop polls: `SLEEP` invoked, exits after `MAX_POLLS` with "reached MAX_POLLS".
  - L2 happy-path ordering: one ready Issue that completes on drain → the dispatch is logged
    **before** any `SLEEP` (proves "no fixed idle wait on the happy path").
  - L3 pre-existing `STOP_FILE` → exits immediately, no dispatch, prints "kill switch".
  - L4 kill switch mid-run: fake `SLEEP` creates the `STOP_FILE` on its first call → loop stops at
    the next iteration (proves "stop at any time").
  - L5 `NIGHT_SHIFT_CONCURRENCY=2` → non-zero exit + "serial only" message.
- Mirror: `scripts/night_shift_run.sh:271-295`; `scripts/night_shift_run.test.sh:374+` (Slice C — bounded-loop / MAX_ITERS stop assertion style)
- Validate: `bash scripts/night_shift_loop.test.sh`

### Task 4: Wire the new test into CI
- File: `.github/workflows/ci.yml`
- Action: UPDATE
- Implement: add `bash scripts/night_shift_loop.test.sh` to the `run:` list (place it after
  `night_shift_run.test.sh` / `night_shift_retry.test.sh`).
- Mirror: `.github/workflows/ci.yml` (existing test list)
- Validate: `bash scripts/night_shift_loop.test.sh` (locally) — CI runs it on push/PR.

### Task 5: Record the trigger-label decision (ADR-0025)
- File: `docs/adr/0025-night-shift-trigger-label-is-ready-for-agent.md`
- Action: CREATE
- Implement: per Pattern 4. **Decision:** the Night Shift trigger label **is** the existing
  `ready-for-agent`; no separate `ready` label. "Ready" in prose is shorthand for it; deliberate
  staging = *not yet* adding the label, deliberate release = adding it; the `in-progress` claim gate
  composes unchanged. **Why over the alternatives:** a distinct `ready` label would require creating
  it, changing the executor default, and dual-labelling every Issue — with no staging capability the
  single label doesn't already give (simplicity-first). Note it back-defines `ready` in
  ADR-0023/0024/CONTEXT/PRD prose, so those append-only ADRs need no edit.
- Mirror: `docs/adr/0023-night-shift-triggers-schedule-not-judge.md:1-79`
- Validate: file exists; H1 + Status/Context/Decision/Consequences present.

### Task 6: Reconcile stale `ready` references (the closeout AC)
- File: `scripts/night_shift_decide.sh`, `scripts/night_shift_run.sh`, `CONTEXT.md`, `.agents/prds/piv-ralph-loop.prd.md`
- Action: UPDATE
- Implement:
  - `night_shift_decide.sh:5-6` — `Issue carries the \`ready\` label` → `… the \`ready-for-agent\` label`.
  - `night_shift_run.sh:4` — `Drives one \`ready\` Issue` → `Drives one \`ready-for-agent\` Issue`;
    `:26` — `(#63 renames)` → `(the trigger label; #63 decided it stays \`ready-for-agent\` — ADR-0025)`.
  - `CONTEXT.md` (Night Shift def ~253/255/261, Day Shift def ~271) — name the real label:
    first use `each \`ready-for-agent\`-labelled **Issue**`, Day Shift `add the \`ready-for-agent\`
    label`, with a parenthetical `(the trigger label — #63/ADR-0025)`.
  - PRD `piv-ralph-loop.prd.md` — replace the "**Trigger-label name is unsettled**" bullet
    (~line 271) with: `**Trigger label = \`ready-for-agent\`** (decided in #63, ADR-0025). \`ready\`
    throughout this PRD is shorthand for it; the \`in-progress\` claim gate composes unchanged.`
- Mirror: existing comment/prose style in each file.
- Validate: `grep -rniE '\bready\b' scripts/ | grep -viE 'ready-for-agent|already'` shows no code
  comment naming a bare `ready` label; `bash scripts/night_shift_loop.test.sh` still green.

### Task 7: Live read-only `select` probe (E2E, no credit spend)
- File: (none — probe only)
- Action: verify
- Implement: from the repo root run `bash scripts/night_shift_loop.sh select` and confirm it prints
  a real grabbable Issue number (e.g. `62`) — grounding the production `gh` path end-to-end. Do
  **not** run `drain`/`loop` as validation (they dispatch real phase sessions).
- Validate: prints a plausible open `ready-for-agent`, non-`in-progress`, non-PR Issue number.

### Task 8: Standalone operator runbook (start / kill switch / observe / teardown)
- File: `.agents/reports/night-shift-loop-runbook.md`
- Action: CREATE
- Implement: mirror the executor runbook's operator-card structure. Sections:
  1. **Purpose + safety rails** — run **only in the dedicated Night Shift clone**, never your
     working checkout (HEAD race, ADR-0024 / CLAUDE.md); the loop drives **real** PRs so it spends
     credit; leave the dangerous-push floor on (ADR-0020); it never merges.
  2. **Preconditions** — reuse the executor runbook §1 (no `ANTHROPIC_API_KEY` shadowing the
     subscription; headless `claude -p` works; `git push` dial graduated by the **operator** by hand;
     dedicated clone on `main`). Reference it, don't duplicate.
  3. **Dry-run first (read-only, no credit):** `bash scripts/night_shift_loop.sh select` → prints
     the Issue the loop would grab next (nothing dispatched).
  4. **Start:** persistent → `bash scripts/night_shift_loop.sh` (optional `NIGHT_SHIFT_POLL_INTERVAL=300`);
     cron → `*/5 * * * * … night_shift_loop.sh drain` (cron supplies the poll cadence; `drain` does one
     pass and exits). Serial (dial = 1), one task at a time.
  5. **Kill switch / stop:** `touch "$NIGHT_SHIFT_STATE_DIR/stop"` — graceful (stops before the next
     task/poll; a task already mid-flight finishes first); `rm` the file to resume; Ctrl-C / `kill -TERM`
     for immediate stop.
  6. **Observe:** `cat "$NIGHT_SHIFT_STATE_DIR/<N>.state"` (phase + attempts); `pgrep -af 'claude -p'`
     (live phase sessions); `/dashboard`.
  7. **Quiescence & stuck tasks:** the loop idles (polling) when the queue drains; a stuck task keeps
     `in-progress` and an escalated one carries the `ESCALATED` marker — both are skipped by design, so
     the loop never spins on them. Un-stick by human triage (fix, then clear the label to re-offer).
  8. **Teardown:** engage the kill switch, confirm stopped; the dedicated clone stays for reuse.
- **Ground every check command (CLAUDE.md do-not / `verify-check-commands`; this runbook's own §5
  ancestor shipped an unrun check — do not repeat that):** before shipping, dry-run each GO/stop
  check against a **known-good AND known-bad** case and confirm it flips, spending **zero** live
  credit by injecting fakes (`NIGHT_SHIFT_RUN=<fake>`, `NIGHT_SHIFT_SLEEP=<fake>`, a temp
  `NIGHT_SHIFT_STATE_DIR`):
  - `select` → a number (fake `gh` has a ready Issue) vs empty (none / all claimed);
  - kill switch → with `stop` present the loop exits + `pgrep` empty vs running without it;
  - concurrency guard → `NIGHT_SHIFT_CONCURRENCY=2` exits non-zero vs `=1` proceeds.
  Note the dry-run evidence inline (mirror the executor runbook's grounding note, its §5).
- Mirror: `.agents/reports/night-shift-thin-executor-runbook.md:1-155`
- Validate: file exists; every check command in it was dry-run known-good + known-bad (evidence noted
  in the runbook or the implement report).

## Validation
- **Unit (offline, the gate):** `bash scripts/night_shift_loop.test.sh` → "All tests passed."
- **Full project gate:** `.claude/validate.sh` (runs `piv_check.sh`); the `validate_gate` Stop hook
  runs it on session end.
- **Regression:** `bash scripts/night_shift_run.test.sh` and `bash scripts/night_shift_decide.test.sh`
  still green (Task 6 only touches comments/prose in those areas).
- **CI:** `.github/workflows/ci.yml` runs the whole `scripts/*.test.sh` set incl. the new file.
- **E2E (read-only):** Task 7 live `select` probe returns a real Issue number.
- **AC mapping:** event-driven happy path → D1/L2 (no sleep while work exists); ~5-min poll → L1/L4;
  skip non-ready → S2 + executor's own gate; concurrency dial default 1 → L5; kill switch → L3/L4;
  claim gate (Route A) → owned by the executor (`night_shift_run.sh:223-235`), select excludes
  `in-progress` (S2); label decided+recorded → Task 5; closeout alignment → Task 6.

## Acceptance Criteria
- [ ] A finished phase/task event-triggers the next immediately — `drain` dispatches back-to-back
      with no `SLEEP` while the ready set is non-empty (D1, L2)
- [ ] A ~5-min poll picks up newly-ready Issues and reconciles missed state — `loop` sleeps
      `POLL_INTERVAL` only when idle, then re-`drain`s from fresh GitHub truth (L1, L4)
- [ ] Issues without `ready-for-agent` are skipped (S2; executor re-checks)
- [ ] Concurrency is a dial defaulting to 1; `!= 1` is refused with a clear message (L5)
- [ ] Operator kill switch stops the loop at any time — `STOP_FILE` + INT/TERM trap (L3, L4)
- [ ] Claim gate (Route A) intact: selection excludes `in-progress`; the executor claims before
      dispatch and releases/keeps-claimed on terminal; ownership by label, not assignee
- [ ] Trigger-label decision made and recorded: `ready-for-agent` (ADR-0025)
- [ ] Every stale bare-`ready` label reference aligned to `ready-for-agent` (Task 6)
- [ ] `bash scripts/night_shift_loop.test.sh` green; added to `ci.yml`; existing tests still green
- [ ] `drain` provably terminates (terminal-exclusion invariant) — no hot-spin, no starvation
- [ ] Standalone operator runbook shipped (`.agents/reports/night-shift-loop-runbook.md`); every
      GO/stop check in it dry-run against known-good + known-bad and seen to flip
