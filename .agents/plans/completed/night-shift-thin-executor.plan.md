# Plan: Night Shift — thin executor (happy-path tracer bullet)

## Summary
Build the **thin executor** that turns the (already-landed) pure decider's happy-path
decisions into real side effects, driving one `ready` Issue all the way to a review-ready
PR with no human between phases. The executor is a shell driver (`scripts/night_shift_run.sh`)
that, per iteration, gathers a durable-artifact snapshot, hands it to
`scripts/night_shift_decide.sh` for the next action, and performs exactly that action:
**claim** the Issue (`in-progress` label, before any worktree), spawn a **fresh, isolated
session per phase** by invoking the project slash command in a separate `claude -p`
subprocess (`/plan` → `/implement` → `/validate`), and let `/validate`'s existing Phase 5
push the branch + open the PR + fire the `pr-ready` notification. It carries **no loop
logic** — every "what next" comes from the decider. The chosen **runtime substrate**
(the issue's HITL decision) is recorded as **ADR-0024**: headless `claude -p` per phase
for structural session isolation, running inside a **dedicated Night Shift clone** to
resolve the HEAD race (CLAUDE.md:121); the recurring event+poll scheduler is deferred to
#63.

## User Story
As a developer, I want the executor to drive a `ready` Issue through Plan → Implement →
Validate unattended and leave me a review-ready PR, so that my only job on a successful
task is code review — and I never manually open a session to advance a phase.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW |
| Complexity | HIGH |
| Systems affected | `scripts/` (new executor + tests), `docs/adr/` (ADR-0024), `.agents/reports/` (probe report). **No change** to `.claude/commands/*`, `.claude/hooks/notify.sh`, `security_guard.py`, or the decider/loop-state scripts. |
| Issue | #61 |

## Assumptions & Risks
Load-bearing claims. The whole slice rests on the first row — it is the issue's HITL
decision and is **ASSUMED** (credit-blocked from full live verification here), de-risked by
the Seam-3 probe as the **first** build step.

| Claim | Status | Evidence (probe + result) or mitigation |
|-------|--------|------------------------------------------|
| A headless `claude -p "/<cmd>"` **expands and executes a project slash command** unattended (the phase-spawning primitive). | **VERIFIED** | Probe (planning session): scratch dir with `.claude/commands/probe-echo.md`, then `env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude -p "/probe-echo" --output-format text < /dev/null` → printed `PROBE_SLASHCMD_OK`, exit 0. Confirms `-p` expands a project slash command and runs its body headless. (First attempt on the inherited API key hit `Credit balance is too low` — see the auth row.) Prior: spike confirmed `claude -p hi` headless + `--permission-mode auto` (`.agents/reports/spike-autonomy-probes-report.md:27-37`). The full PIV drive (`/plan`→`/implement`→`/validate`→PR) is still exercised end-to-end by the Task 6 integration probe (PRD Seam 3). |
| Spawned sessions run in the **unattended/graduated posture** (auto mode + `git push` graduated `ask→allow`). | **ASSUMED** | Project/local-scope `defaultMode:auto` is *ignored*; only user-scope `~/.claude/settings.json` or the `--permission-mode` flag grants auto (`spike-...report.md:16-19, 27-30`). On-switch = operator graduates `Bash(git push *)` ask→allow in the live dial (#59, landed). Mitigation: the Task 2 probe runs under the real graduated posture; executor invokes `claude -p` inheriting user-scope settings (optionally `--permission-mode`, confirmed in probe). Dangerous-push floor (`security_guard.py`, ADR-0020) stays enforced independently. |
| Spawned `claude -p` sessions run on the operator's **claude.ai subscription**. | **VERIFIED** | A stale, unfunded `ANTHROPIC_API_KEY` was exported in `~/.bashrc` (lines 129/133) and **took precedence** over the claude.ai login (`Credit balance is too low`). **Resolution: remove the stale key** (an old test key, no longer used), so `claude -p` defaults to the subscription credential at `~/.claude/.credentials.json`. Probe (key unset): `claude -p "…" < /dev/null` → `SUBOK`, exit 0. Operational precondition (ADR-0024): the Night Shift host must not export a stale `ANTHROPIC_API_KEY`. |
| **`GATE=green ⟺ plan archived to `.agents/plans/completed/{slug}.plan.md`** is the only faithful "validate passed" signal. | **VERIFIED** | `scripts/piv_check.sh:62-86` (the mechanical `.claude/validate.sh`) goes green as soon as plan+report exist — *before* `/validate` runs — so the executor must **not** compute GATE from `.claude/validate.sh` or the decider would skip `/validate` (green → `open-pr` beats `run-validate`, `night_shift_decide.test.sh:48`). Only `/validate` Phase 5 `git mv`s the plan to `completed/` on green (`.claude/commands/validate.md:67-87`). So `completed/` presence = validate-passed. |
| `/validate` **already** pushes the branch + opens the PR + fires the `pr-ready` notify on green. | **VERIFIED** | `.claude/commands/validate.md:92-133`: `git push -u origin {branch}`, `gh pr create … Closes #{N} … ## 變更說明`, then `notify.sh pass "Validate PASS" "{branch}: PR ready"` (`:128-133`). ⇒ The executor does **not** reimplement push/PR/notify; the `open-pr` decision delegates to `/validate` (idempotent re-entry). This honors "the loop does not alter the PIV artifact lifecycle". |
| `/implement` is the actor that **branches `feat/{N}-{slug}`, creates the worktree, and seeds the plan as the branch's first commit**. | **VERIFIED** | `.claude/commands/implement.md:42-43` (branch), `:53` (worktree add), `:66-83` (seed plan as first commit), `:58-60` (phases 3–5 in worktree). ⇒ The executor passes a plan path to `/implement` and does **not** branch/seed itself. |
| Claim is a **label, not an assignee**; labels `ready-for-agent` (trigger) + `in-progress` (claim) exist; single `gh` identity. | **VERIFIED** | `gh label list`: `ready-for-agent`, `in-progress` ("Claimed by a worker (Night Shift or human); pickup skips these") both exist; `gh api user` → single identity `dylankuo84137`. #61 carries `ready-for-agent`. |
| The executor must run where **no human runs interactive HEAD-mutating commands** (HEAD race). | **VERIFIED → resolved by decision** | CLAUDE.md:121 names the HEAD race and defers the durable fix ("Night Shift in its own clone") to this substrate decision. **Decision (HITL): dedicated Night Shift clone** — recorded in ADR-0024. |

## Patterns to Follow

**Decider contract — the executor's only source of "what next"** (`scripts/night_shift_decide.sh:13-26`):
```bash
# Inputs (env, booleans "1"/"0"; GATE ∈ unrun|green|red; ATTEMPTS int):
#   ISSUE_READY PLAN_PRESENT REPORT_PRESENT GATE PR_OPEN ESCALATED ATTEMPTS
# Output (one token): run-plan|run-implement|run-validate|retry-reimplement|retry-replan|escalate|open-pr|noop
# This slice emits only: run-plan|run-implement|run-validate|open-pr|noop
# SOURCE: scripts/night_shift_decide.sh:13-26
```
Invoke it exactly as the test does — clean env, vars passed in (`scripts/night_shift_decide.test.sh:14`):
```bash
decision="$(env -i ISSUE_READY="$r" PLAN_PRESENT="$p" REPORT_PRESENT="$rep" \
                  GATE="$g" PR_OPEN="$pr" ESCALATED=0 bash "$DECIDER")"
# SOURCE: scripts/night_shift_decide.test.sh:14
```

**Durable per-task state** — record current phase (attempts untouched; that's #62) (`scripts/loop_state.sh:24-67`, store dir `:6`):
```bash
bash scripts/loop_state.sh set-phase "$task" implement   # task = Issue number, e.g. 61
bash scripts/loop_state.sh get-phase "$task"
# State lives in ${NIGHT_SHIFT_STATE_DIR:-.night-shift}/<task>.state (gitignored).
# SOURCE: scripts/loop_state.sh:6,24-67
```

**Worktree path resolution** (exact-match; never forward-scan porcelain) (`scripts/worktree_path.sh`):
```bash
wt="$(git worktree list --porcelain | bash scripts/worktree_path.sh "feat/${N}-${slug}")"
# SOURCE: scripts/worktree_path.sh:1-29 ; CLAUDE.md Do-not (clean-worktree-wrong-worktree)
```

**Notification (pr-ready) — fired by `/validate`, NOT the executor** (`.claude/hooks/notify.sh`, `.claude/commands/validate.md:128-133`):
```bash
# notify.sh <level> <title> <message> ; pr-ready ⇒ level "pass" (bell + ntfy)
# Already wired inside /validate Phase 5 — the #58 call site. #61 adds NO notify code.
```

**Test style — env-injected fakes + assert_eq + mktemp workdir + trap** (`scripts/loop_state.test.sh:1-18,86-94`); stub externals by **dependency-injection** the way `notify.test.sh` shadows `curl` and logs calls, but via env (`NIGHT_SHIFT_CLAUDE`, `NIGHT_SHIFT_GH`) pointing at logging fakes that also simulate artifact creation. Mirror the footer (`FAILURES` count → exit code).

**Probe/report style** (`.agents/reports/spike-autonomy-probes-report.md`): command + observed result per probe; explicit GO/NO-GO.

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `docs/adr/0024-night-shift-executor-substrate-headless-claude-own-clone.md` | CREATE | Record the runtime-substrate decision (AC: "substrate chosen and recorded"). |
| `scripts/night_shift_run.sh` | CREATE | The thin executor: snapshot → decide → dispatch; claim gate; per-phase `claude -p`. |
| `scripts/night_shift_run.test.sh` | CREATE | Unit-test the deterministic seams (snapshot mapping, dispatch, claim gate, terminal no-op) with `claude`/`gh`/`git` injected. |
| `.agents/reports/night-shift-thin-executor-report.md` | CREATE (in `/implement`) | Implementation report + the Seam-3 probe results (GO/NO-GO). |
| `.github/workflows/ci.yml` | UPDATE | Add `night_shift_run.test.sh` to the test suite (mirror existing `*.test.sh` entries). |

Dependency order: ADR-0024 (Task 1) → probe gate (Task 2) → executor seams TDD (Tasks 3–5) → end-to-end probe (Task 6) → CI wiring (folded into Task 5).

## Architecture (one screen)

`scripts/night_shift_run.sh <issue-number>` — externals dependency-injected:
`NIGHT_SHIFT_CLAUDE=${NIGHT_SHIFT_CLAUDE:-claude}`, `NIGHT_SHIFT_GH=${NIGHT_SHIFT_GH:-gh}`,
`NIGHT_SHIFT_TRIGGER_LABEL=${NIGHT_SHIFT_TRIGGER_LABEL:-ready-for-agent}` (final name is #63's
call; parameterized so the rename is one env default), `NIGHT_SHIFT_STATE_DIR` (shared with
loop_state), `NIGHT_SHIFT_ROOT` (the clone's main checkout; default = repo root).

```
main(N):
  # ── selection / claim gate (Route A) ──
  has_label(N, in-progress) → echo "skip: already claimed"; exit 0      # never double-grab
  has_label(N, trigger)?    → no: echo "skip: not ready"; exit 0
  claim(N)                  # add in-progress  ← BEFORE any worktree (PRD invariant)
  # ── drive: mechanical, NOT loop logic (every action chosen by the decider) ──
  for i in 1..MAX_ITERS:               # MAX_ITERS safety cap (default 6); prevents runaway
    snap = gather_snapshot(N)          # artifacts → decider env vars
    d    = decide(snap)                # = night_shift_decide.sh ; the ONLY policy
    case d:
      noop)          release(N); exit 0          # terminal (PR open) → drop the claim
      run-plan)      claude_run "$ROOT"  "/plan ${N}"                 ; set-phase N plan
      run-implement) claude_run "$ROOT"  "/implement ${planpath}"     ; set-phase N implement
      run-validate)  claude_run "$(wt)"  "/validate ${planpath}"      ; set-phase N validate
      open-pr)       claude_run "$(wt)"  "/validate ${planpath}"      # idempotent fallback → /validate pushes+PRs+notifies
  echo "iteration cap hit"; exit 3     # safety stop (retry/escalation is #62)

claude_run(dir, cmd):  ( cd "$dir" && "$NIGHT_SHIFT_CLAUDE" -p "$cmd" < /dev/null )
   # blocking; return = phase-complete event. Runs on the claude.ai SUBSCRIPTION
   # (~/.claude/.credentials.json) — the stale test ANTHROPIC_API_KEY was removed from the host, so no
   # per-call unset is needed. stdin=/dev/null avoids the 3s stdin wait observed in planning. [VERIFIED]

gather_snapshot(N):                    # GATE faithful to the /validate SESSION, not piv_check
  slug = resolve_slug(N)               # see below; "" before /plan
  branch = slug ? "feat/${N}-${slug}" : ""
  wt = branch ? worktree_path(branch) : ""
  root = wt ? wt : "$ROOT"             # once the worktree exists, artifacts live there
  ISSUE_READY   = has_label(N, trigger) ? 1 : 0
  PLAN_PRESENT  = (slug && (exists root/.agents/plans/${slug}.plan.md ||
                           exists root/.agents/plans/completed/${slug}.plan.md)) ? 1 : 0
  REPORT_PRESENT= (slug && exists root/.agents/reports/${slug}-report.md) ? 1 : 0
  GATE          = (slug && exists root/.agents/plans/completed/${slug}.plan.md) ? green : unrun
  PR_OPEN       = (branch && gh pr list --head "$branch" --state open --json number ≠ []) ? 1 : 0
  ESCALATED     = 0                     # out of scope (#60/#62)

resolve_slug(N):                        # restartable, no extra persisted state
  branch = git branch --list "feat/${N}-*"  → strip "feat/${N}-" → slug   # post-implement (authoritative)
  else grep '| Issue | #N |' in $ROOT/.agents/plans/*.plan.md → slug      # post-plan, pre-implement (draft)
  else ""                                                                 # pre-plan
```

**Why this is "thin / no loop logic":** the `for` loop is a mechanical "keep asking the
decider until it says `noop`"; it contains zero policy. Which action runs is 100% the
decider's output. The executor only knows *how* to perform each action, never *whether*.

**Happy-path trace (Issue #61):**
`ready, no plan → run-plan` (claim, `/plan 61`, draft written in clone) →
`plan present → run-implement` (`/implement <plan>`: branches `feat/61-<slug>`, worktree,
seeds plan as first commit, writes report) →
`report present, gate unrun → run-validate` (`/validate <plan>` in worktree: gate+E2E green
→ archives plan to `completed/`, pushes, opens PR, fires `notify pass`) →
`PR open → noop` (release `in-progress`; done). `open-pr` is reached only if a green
gate left no PR (push/PR failed) → re-run `/validate` (idempotent); persistent failure is
#62's escalation, bounded here by `MAX_ITERS`.

## Tasks
Ordered, atomic, each independently verifiable.

### Task 1: Record the runtime substrate — ADR-0024
- File: `docs/adr/0024-night-shift-executor-substrate-headless-claude-own-clone.md`
- Action: CREATE
- Implement: Mirror the existing ADR format (Status / Context / Decision / Consequences;
  see `docs/adr/0023-night-shift-triggers-schedule-not-judge.md`). Decide, with rationale:
  (1) **phase sessions = headless `claude -p "/<phase>"` subprocesses** (one OS process per
  phase ⇒ structural fresh-session isolation; the only mechanism that loads project slash
  commands + hooks + clean context); (2) **executor runs in a dedicated Night Shift clone**
  (resolves the HEAD race, CLAUDE.md:121 — the human's checkout and the loop's checkout are
  different working trees over the same repo); (3) **recurring event+poll scheduler deferred
  to #63** (this slice does a single end-to-end drive). Reject cron (external infra, none in
  repo), `/loop`+`/routines` (a long-lived chained session — PRD Out-of-Scope), Workflow
  subagents (not full PIV sessions). Record the **auth posture**: phase sessions run on the
  operator's **claude.ai subscription** (`~/.claude/.credentials.json`); the host must **not**
  export an `ANTHROPIC_API_KEY`, which would take precedence over the login (a stale unfunded
  test key was found in `~/.bashrc` and removed). Note other operational preconditions:
  graduated push dial (#59); `< /dev/null` stdin. Reference ADR-0023 (schedule-not-judge) and
  ADR-0013/0014 (unchanged lifecycle).
- Mirror: `docs/adr/0023-night-shift-triggers-schedule-not-judge.md`
- Validate: file exists, numbered 0024, English (canonical doc — CLAUDE.md Do-not);
  `bash .claude/validate.sh` passes on the branch (ADR is a doc change but rides the feature
  branch, so the plan-first-commit + report invariants still apply).

### Task 2: Probe gate (Seam 3, FIRST) — confirm a real PIV slash command runs unattended on the subscription
- File: throwaway scratch + a probe section appended to the report (Task added to report in Phase 4)
- Action: PROBE (no production code trusted until this is GREEN)
- Implement: The phase-spawning primitive is already VERIFIED in planning (`probe-echo` →
  `PROBE_SLASHCMD_OK`, exit 0, on the subscription via `env -u ANTHROPIC_API_KEY`). This task
  confirms it for a **real PIV command** end-to-end: under the **graduated** posture, in a
  scratch clone, on a throwaway `ready` Issue, run
  `claude -p "/plan <N>" < /dev/null` and
  confirm it (a) runs on the **subscription** (host exports no `ANTHROPIC_API_KEY`), (b) runs unattended
  (no permission stall), (c) writes `.agents/plans/<slug>.plan.md`. Record command + observed
  result + GO/NO-GO. If NO-GO, **stop and escalate** — the substrate is invalid (verification-led
  gate, CLAUDE.md Conventions). Confirm whether `--permission-mode` is needed (flag vs the
  operator's user-scope auto posture).
- Mirror: `.agents/reports/spike-autonomy-probes-report.md`
- Validate: probe result recorded with explicit GO/NO-GO; on GO, proceed to Task 3.

### Task 3: Snapshot gatherer (TDD)
- File: `scripts/night_shift_run.sh` (+ `scripts/night_shift_run.test.sh`)
- Action: CREATE
- Implement: Write `night_shift_run.test.sh` cases FIRST, then `gather_snapshot` +
  `resolve_slug` to pass them. Externals injected via `NIGHT_SHIFT_GH` (fake `gh` that prints
  canned labels / PR JSON) and fixture `.agents/` trees under a `mktemp` root. Assert the
  artifact→env mapping for each happy-path state, **including the faithfulness case**:
  *report present + plan NOT in `completed/` ⇒ GATE=unrun (NOT green)* and *plan in
  `completed/` ⇒ GATE=green*. Assert `resolve_slug` resolves from the branch post-implement
  and from the draft pre-implement.
- Mirror: `scripts/loop_state.test.sh:1-18` (harness), `scripts/night_shift_decide.test.sh:14`
  (decider invocation)
- Validate: `bash scripts/night_shift_run.test.sh` → all pass.

### Task 4: Decision dispatch (TDD)
- File: `scripts/night_shift_run.sh` (+ tests)
- Action: UPDATE
- Implement: Add `dispatch <decision> <N>` and `claude_run`. Inject `NIGHT_SHIFT_CLAUDE` =
  a fake that **logs its args** and **simulates the phase's artifact effect** (e.g. `/plan`
  writes a draft; `/implement` creates branch+worktree+report; `/validate` archives plan +
  prints a fake PR). Tests assert each decision invokes the correct command in the correct
  cwd (clone root for plan/implement, worktree for validate), that the executor adds **no**
  push/PR/notify of its own (delegated to `/validate`), and that `open-pr` re-invokes
  `/validate`. Assert `set-phase` is recorded per phase.
- Mirror: `scripts/notify.test.sh` (PATH/env-shadowed fake that logs calls)
- Validate: `bash scripts/night_shift_run.test.sh` → all pass.

### Task 5: Drive loop + claim gate + CI wiring (TDD)
- File: `scripts/night_shift_run.sh`, `scripts/night_shift_run.test.sh`, `.github/workflows/ci.yml`
- Action: UPDATE
- Implement: Add `main` (selection guard → claim → bounded decide/dispatch loop → release on
  terminal). Tests assert: **skip when already `in-progress`** (no double-grab); **`in-progress`
  added before any worktree-creating dispatch** (claim-before-worktree ordering); **terminal
  no-op** (PR_OPEN ⇒ `noop` ⇒ release, no duplicate `gh pr create`); **full happy-path drive**
  reaches `noop` via the decider for every step (proves "no loop logic"); **MAX_ITERS** stops a
  runaway. Add `night_shift_run.test.sh` to `.github/workflows/ci.yml` alongside the other
  `*.test.sh`.
- Mirror: `scripts/loop_state.test.sh` (namespacing/independence cases), `.github/workflows/ci.yml`
  (existing test entries)
- Validate: `bash scripts/night_shift_run.test.sh` pass; `bash .claude/validate.sh` green.

### Task 6: End-to-end integration probe (Seam 3) — ready Issue → open PR
- File: probe results appended to `.agents/reports/night-shift-thin-executor-report.md`
- Action: PROBE
- Implement: In the dedicated Night Shift clone (graduated posture; host exports no
  `ANTHROPIC_API_KEY`, so phase sessions run on the subscription), run
  `bash scripts/night_shift_run.sh <test-issue-N>` against a real throwaway `ready` Issue.
  Observe and record: fresh session per phase (3 distinct `claude -p` processes), worktree
  created at `../<repo>-feat/<N>-<slug>`, plan seeded as first commit, branch pushed, PR
  opened (never merged), `pr-ready` notify fired, `in-progress` removed on terminal. This is
  the executor's primary verification (PRD: executor = probe, not unit test). Record GO/NO-GO.
- Mirror: `.agents/reports/spike-autonomy-probes-report.md`
- Validate: a pushed branch + an open PR exist for the test Issue; the Issue ends without
  `in-progress`; the PR is unmerged.

## Validation

**Mechanical gate** (run from the feature worktree; `validate_gate.py` Stop hook also runs it):
```bash
bash scripts/night_shift_run.test.sh     # new executor unit tests — all pass
bash scripts/night_shift_decide.test.sh  # decider unchanged — still green (regression)
bash scripts/loop_state.test.sh          # state store unchanged — still green (regression)
bash .claude/validate.sh                 # piv_check: plan is first commit + report exists
```

**End-to-end (the tracer bullet — Task 6 probe, recorded in the report):**
- [ ] A `ready` Issue with a green path produces a **pushed branch + an opened PR**.
- [ ] Each phase ran in a **fresh isolated session** (3 separate `claude -p` processes).
- [ ] Each task ran in its **own git worktree** (sibling `../<repo>-feat/<N>-<slug>`).
- [ ] Plan is the branch's **first commit**; `/validate` archived it to `completed/` on green
      (lifecycle unchanged).
- [ ] The loop **never merged** the PR.
- [ ] `pr-ready` notification fired when the PR opened (via `/validate` Phase 5).
- [ ] **Claim gate:** selection skipped an already-`in-progress` Issue; `in-progress` added
      **before** the worktree; removed on terminal. Ownership is a **label** (single `gh`
      identity).
- [ ] Executor carries **no loop logic** (every action came from `night_shift_decide.sh`)
      and added **no** notify/push/PR code of its own.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors (new + regression test suites green; `.claude/validate.sh` green)
- [ ] Follows existing patterns (decider invocation, loop_state, worktree_path, test harness, ADR format)
- [ ] Every external-behavior claim is VERIFIED by a probe, or carried as an explicit risk
      (the headless-slash-command claim is gated GREEN by the Task 2 probe before any executor
      code is trusted)
- [ ] End-to-end behavior verified (Task 6 probe: ready Issue → open PR, recorded in the report)
- [ ] Runtime substrate chosen and recorded (ADR-0024)
- [ ] No change to `/plan`·`/implement`·`/validate`, `notify.sh`, `security_guard.py`, the
      decider, or the loop-state store (lifecycle + #58/#60/#62/#63 scope boundaries respected)

## Scope boundaries (explicit non-goals)
- **Notification reshape (#58):** removing the per-step `permission_prompt`/`idle_prompt`
  `info` hooks in `settings.shared.json` and asserting the two-fire contract is #58, not #61.
  #61 only relies on `/validate`'s existing `pr-ready` (`pass`) fire.
- **Retry ladder + escalation + terminal-state hardening (#60/#62):** the executor stops
  (exit non-zero) on a red gate or iteration-cap; retry/re-plan/escalate and robust terminal
  no-op are #62 (decider rungs are #60). `ATTEMPTS`/`ESCALATED` are passed as `0`.
- **Recurring trigger (#63):** event+poll scheduling, queue selection across many Issues,
  serial→N concurrency dial, kill switch, and the `ready`-vs-`ready-for-agent` label rename
  are #63 (which is blocked by this issue). #61 does a single end-to-end drive.
- **No edits to canonical docs** beyond the new ADR; ADR stays English (CLAUDE.md Do-not).
