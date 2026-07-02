# PIV Ralph Loop (unattended PIV orchestration — the Night Shift scheduler)

Status: draft-for-review
Created: 2026-06-28

One-line: a scheduling layer that drives each `ready`-labelled Issue through the entire
Plan → Implement → Validate loop with no human in the middle — the human writes the Issue
and reviews the PR; everything between runs in the existing worktree sandbox.

---

## Problem Statement

From the developer's perspective:

"Unattended Autonomy" today only removed *input* friction — I no longer approve each tool
call inside the sandbox. But it left *orchestration* friction fully in place: **I am still
the scheduler.** After `/plan` finishes I have to notice, open a fresh session, and type
`/implement`; after that finishes I have to notice again and type `/validate`. Three manual
handoffs per task, each requiring me to be present and paying attention.

The "unattended" in Unattended Autonomy means "no per-tool-use approval," **not** "no
per-phase human initiation." So a queue of ready work can't drain itself overnight — it
drains only as fast as I personally shepherd each task through plan → implement → validate.
The human is the bottleneck *between* phases, not in the keystrokes *inside* them.

## Solution

A scheduling layer — the **Night Shift** — that drives each task through the entire PIV
loop with no human in the middle. The human's only two touchpoints become the bookends:
write an Issue and label it `ready` (the Day Shift planning input), and review the resulting
PR (the boundary gate). Everything between is automated inside the existing worktree sandbox.

The loop is a **per-task state machine** over durable artifacts (the Issue, the plan file,
the report file, git, the per-task attempt count): a `ready` Issue triggers `/plan`, the
resulting plan triggers `/implement`, the resulting report triggers `/validate`, and a green
gate opens a PR for human review.

Each phase runs in its **own fresh, isolated session** — the loop automates the act of "open
a new session and type the next command" that the human does today; it does **not** collapse
the three phases into one long-lived context (that would forfeit session isolation and rot
the context). On a red gate the loop self-heals along a **bounded retry ladder**, and
escalates to a human only when a task is genuinely stuck. Notifications stop nagging the
human to push work forward and fire only at the two moments a human is actually wanted: a PR
is ready, or a task is stuck.

## User Stories

1. As a developer, I want to write an Issue and add a `ready` label, so that the loop picks
   it up without any further action from me.
2. As a developer, I want the loop to run `/plan`, `/implement`, and `/validate` for a
   `ready` Issue automatically, so that I never manually open a session to advance a phase.
3. As a developer, I want to come back to a review-ready PR, so that my only remaining job on
   a successful task is code review.
4. As a developer, I want each phase to run in its own fresh isolated session, so that
   context rot from a long-lived loop never degrades plan/implement/validate quality.
5. As a developer, I want each task to run in its own git worktree sandbox, so that
   sequential (and later parallel) tasks never corrupt each other's working tree.
6. As a developer, I want the plan committed as the branch's first commit (as today), so that
   `/validate` reads it as a tracked file and the durable record is preserved.
7. As a developer, I want the loop's "what next" decision derived from files and git state
   (plan present? report present? gate green?), so that the loop is restartable and never
   depends on an agent's memory.
8. As a developer, when `/validate` fails, I want the loop to retry along a bounded ladder
   (re-implement, then re-plan) rather than re-run the same failing step forever, so that a
   bad plan is corrected instead of amplified.
9. As a developer, I want the loop to give up after K attempts and escalate, so that a task
   that can never pass cannot silently burn tokens all night.
10. As a developer, I want exactly one escalation signal when a task is stuck, so that I'm
    pulled in only when human judgment is genuinely required.
11. As a developer, I want the per-step "come push the next phase" notifications gone, so
    that I'm no longer interrupted to do work the loop can do itself.
12. As a reviewer, I want a "PR ready" notification when a task reaches a green gate and
    opens a PR, so that I don't have to poll the PR queue.
13. As a reviewer, I want human PR review to remain the single mandatory gate before merge,
    so that nothing reaches the default branch without a person approving it.
14. As an operator, I want to enable the whole Night Shift by flipping a single dial
    (`git push: ask → allow`), so that turning autonomy on or off is one deliberate,
    auditable action.
15. As an operator, I want the dangerous-push deny floor (force-push, push-to-default-branch)
    to remain enforced regardless of the dial, so that graduating benign push never weakens
    the hard safety floor.
16. As an operator, I want to stop the loop at any time, and I want the loop to stop itself
    on stuck tasks, so that I keep a kill switch and the loop has a natural quiescence.
17. As an operator, I want to run the loop serially (one task at a time) in v1, so that I can
    prove the engine is correct before increasing blast radius.
18. As an operator, I want concurrency to be a guarded dial that today enforces serial (=1 —
    any other value is rejected), so that v1 blast radius stays bounded; graduating to N is
    flagged as later work that requires building real parallel dispatch, not just raising the
    number.
19. As an operator, I want a ~5-minute poll to discover newly-`ready` Issues and confirm the
    loop is alive, so that freshly-labelled work gets picked up and a wedged loop is visible.
20. As an operator, I want a finished phase to immediately trigger the next phase
    (a synchronous zero-idle drain — the phase call returns and the loop re-selects at once,
    in one process, not an async event), so that a task doesn't idle up to 5 minutes at each
    transition.
21. As an operator, I want the loop to skip Issues not labelled `ready`, so that I can stage
    work and release it to the Night Shift deliberately.
22. As a maintainer, I want the loop's next-action logic isolated as a pure decider, so that
    I can exhaustively test the state machine offline without spawning sessions or spending
    tokens.
23. As a maintainer, I want the side-effecting executor kept thin, so that loop correctness
    lives in the testable decider and not in hard-to-test glue.
24. As a maintainer, I want the retry count and current phase stored as durable per-task
    state, so that the loop resumes correctly after a crash or restart.
25. As a maintainer, I want the notification reshape covered by tests asserting notify fires
    only on escalation and PR-ready, so that per-step nagging cannot silently regress back in.
26. As a developer, I want the loop to assume Issues are independently-grabbable in v1, so
    that serial execution has a simple, well-defined contract before dependency-aware
    scheduling is considered.
27. As a developer, I want the vocabulary reconciliation (Ralph Loop / Night Shift / Day
    Shift terms, the polling-vs-interrupt reframing, ADR-0010) handled in a dedicated
    `grill-with-docs` session before implementation, so that canonical docs don't silently
    contradict themselves.
28. As a reviewer, I want a stuck-task escalation to name which phase failed and how many
    attempts were made, so that I can triage it quickly.
29. As an operator, I want the loop to be a no-op on tasks already in a terminal state (PR
    open, or escalated), so that it doesn't re-open or duplicate work.
30. As a developer, I want `/validate` to keep archiving the plan to `completed/` on green
    (as today), so that the loop does not change the existing PIV artifact lifecycle.
31. As an operator, I want to see which tasks are in which loop phase at a glance (extending
    `/dashboard`), so that I can observe the Night Shift's progress.
32. As an operator, I want the loop never to auto-merge a PR, so that the human review gate
    is structurally impossible to bypass.
33. As an operator sharing the Issue queue with the loop, I want each worker to claim a task
    (the `in-progress` label) before working it and to skip already-claimed tasks, so that the
    Night Shift and I (or future parallel workers) never grab the same Issue and open
    duplicate branches/PRs.

## Implementation Decisions

- **The loop is a per-task state machine.** State is derived from durable artifacts only —
  the Issue (and its `ready` label), the plan file (`.agents/plans/{name}.plan.md`), the
  report file (`.agents/reports/{name}-report.md`), the validate gate verdict, the per-task
  attempt count, and the PR state. No state lives in agent memory.

- **Three modules, drawn at the test seams:**
  1. **Next-action decider (pure).** Input = a task-state snapshot; output = one decision
     from a closed set: `run-plan | run-implement | run-validate | retry-reimplement |
     retry-replan | escalate | open-pr | noop`. No side effects. All loop logic lives here.
     Same shape as `piv_check.sh` (reads git/fs state → emits a verdict), but emitting a
     next-action.
  2. **Durable per-task loop state.** Records current phase and attempt count, surviving
     restarts. The exact store is a `/plan`-phase decision (candidates: the Issue itself, a
     state record alongside the branch, git-native state); the decider's only contract is
     that it can read "attempts so far" and "current phase."
  3. **Thin executor / driver.** Maps a decision to its side effect: spawn a fresh isolated
     session for the named phase, create/enter the worktree, run the phase command, push and
     open the PR, fire notifications. Carries no loop logic — everything is pushed into the
     decider.

- **Each phase = a fresh isolated session.** The executor spawns a new session per phase (it
  automates the human's "open a new session" action) and MUST NOT chain phases inside one
  long-lived context. Session isolation per phase is an invariant, not an optimization
  (CLAUDE.md Smart Zone; the Ralph note's central warning that a single long loop session is
  "a more complex Ralph Loop without the protection of session isolation").

- **Trigger model = hybrid.** A synchronous zero-idle drain on the happy path (each finished
  phase returns and the loop re-selects the next work at once, in one process — there is no
  async event), with a ~5-minute poll as a safety net that (a) discovers newly-`ready`
  Issues and (b) provides liveness. The runtime substrate (cron /
  `/loop`+`/routines` / a Workflow engine) is deliberately NOT fixed here — it is a
  `/plan`-phase decision. This PRD fixes only behavior.

- **Failure = bounded retry ladder, then escalate.** On a red gate: attempt 1 → route to
  `/retroactive` or re-run `/implement`; attempt 2 → re-run `/plan` (suspect the plan
  itself); at K (default 2–3) → stop the task and fire a single escalation. The re-plan rung
  is the structural guard against bad-plan amplification — the dominant risk of automating
  `/plan`, which is the scope chosen here.

- **Notification reshape.** `notify.sh` survives; its callers change. Remove the per-step /
  per-phase prompts and the permission/idle `Notification` hooks (no human is present
  mid-loop). Keep exactly two fires: `escalate` (task stuck after K) and `pr-ready` (green
  gate, PR opened). This is the precise meaning of "remove the notification mechanism": the
  mechanism stays, its triggers shrink.

- **Push graduation is the on-switch.** Enabling the loop requires graduating `git push` from
  `ask` to `allow` (ADR-0017's supervised→unattended dial). The dangerous-push deny floor in
  `security_guard.py` (force-push, push-to-default-branch; ADR-0020) stays enforced
  independently, so benign-push graduation never relaxes the hard floor.

- **Concurrency is a guarded dial, default 1.** v1 runs serial (one task through the full
  pipeline at a time); the dial today is only an *enforce-serial guard* — any value ≠ 1 is
  rejected and there is no parallel-dispatch path. The design reserves the existing `piv-loop`
  "parallel-implement / serial-landing" protocol as the graduation path to N, but graduating is
  real parallel-dispatch work, not just raising the number — a later, deliberate action.

- **Exactly one human gate (PR review).** The loop never auto-merges. `/validate` continues
  to archive the plan to `completed/` on green (ADR-0013); the loop does not alter the PIV
  artifact lifecycle.

- **Scope entry = a `ready`-labelled, independently-grabbable Issue.** v1 assumes no
  cross-Issue dependencies; dependency-aware scheduling is out of scope.

- **Issue ownership = a claim gate (label, not assignee).** The Issue queue is a shared
  resource — the Night Shift, a human, and (once concurrency graduates past 1) parallel
  workers all read the same trigger-labelled list. Selection therefore takes only Issues that
  are trigger-labelled **and NOT** `in-progress`; a worker **claims** a task by adding the
  `in-progress` label **before** it creates the worktree/branch, and the claim is removed or
  superseded once the task is terminal (PR open / escalated). This is the mechanism behind
  "independently-grabbable" (US-26, US-33): grabbable means claimable. Ownership is a
  **label, not an assignee** — assignee claiming would need two distinct GitHub identities,
  and two identities on one machine fight over `gh`'s single global active account
  (`gh auth switch` is global state); a label claim works with one identity, so the human and
  the loop can share a machine. Claim mechanics land in #63 (selection) and #61 (claim before
  worktree); this PRD fixes only the ownership behavior.

- **Vocabulary reconciliation is a blocking predecessor (gate-0).** A dedicated
  `grill-with-docs` session must reconcile CONTEXT.md (the "polling → interrupt" framing
  becomes "interrupt for the two human-wanted events; poll as the loop's scheduling /
  safety-net mechanism"), clarify ADR-0010 (a mechanical trigger may *schedule* a phase but
  never *judge* semantic completion — that judgment stays inside the phase, carried by the
  report and the gate), and admit the new terms (Ralph Loop, Night Shift, Day Shift). That
  session's PR body must carry a Traditional Chinese `## 變更說明` (ADR-0022). This PRD only
  names the terms; it does not edit canonical docs.

## Testing Decisions

- **What a good test is here:** asserts externally-observable behavior — the decision emitted
  for a given state; whether notify was called and with what level — never internal
  structure. Because the decider is a function from state to decision, that IS its external
  behavior, so it is testable with no mocking of sessions or git.

- **Seam 1 — decider (the main test surface).** Table-driven tests enumerating every
  state-machine edge and the retry ladder: `ready` Issue + no plan → `run-plan`; plan present
  + no report → `run-implement`; report present + ungated → `run-validate`; green →
  `open-pr`; red & attempts<K → `retry-reimplement` then `retry-replan` per the ladder; red &
  attempts≥K → `escalate`; PR open or escalated → `noop`. Loop correctness is proven here.
  Prior art: `scripts/piv_check.sh` (state → verdict) and its test style.

- **Seam 2 — durable state.** Feed the decider varying recorded attempt counts and phases;
  assert the transition to `escalate` lands exactly at K, and that a restart re-derives the
  same decision (idempotent on identical state).

- **Seam 3 — executor (integration probe, not unit test).** Verify empirically — in the
  style of `spike-autonomy-probes` — that each phase invocation gets a fresh/clean context
  (session isolation), the worktree is created, and a green gate yields a pushed branch +
  opened PR. Kept deliberately thin so little logic needs this slower harness.

- **Seam 4 — notification reshape.** In the style of `scripts/notify.test.sh`: assert notify
  fires on `escalate` and `pr-ready`, is NOT called on any per-step transition, and the
  permission/idle nudge hooks are gone.

- **Modules tested:** the decider (exhaustive), durable-state reads (escalation threshold +
  idempotent restart), the notify callers (reshape). The executor is covered by probe only.

## Out of Scope

- Auto-merging PRs. Human PR review stays the single mandatory gate; the loop opens PRs,
  never lands them.
- Multi-repo orchestration / a cross-repo control plane. Single repo only.
- Any change to the worktree sandbox or the `security_guard.py` deny floor.
- A long-lived single `/loop` session that chains phases in one context. Session isolation
  per phase is mandatory.
- Fixing the runtime substrate (cron vs `/loop`+`/routines` vs Workflow). A `/plan`-phase
  decision.
- v1 concurrency > 1. Serial first; N is a later graduation.
- Dependency-aware scheduling. v1 assumes independently-grabbable, `ready`-labelled Issues.
- Editing CONTEXT.md / ADRs. That is the gate-0 `grill-with-docs` session's job, in its own
  PR.
- Auto-generating Issues. The human writes the Issue; the loop starts at `/plan`.

## Further Notes

- **Blocking predecessor.** The gate-0 `grill-with-docs` vocabulary reconciliation must land
  first. `to-issues` should slice it as Issue #1, with the loop work depending on it.
- **"Polling → interrupt" is not thrown away.** Interrupts still carry the two human-wanted
  events (escalation, PR-ready); polling returns only as the loop's own scheduling /
  safety-net mechanism, not as the human's status-tracking tool.
- **The biggest accepted risk** of full P+I+V automation (vs. human-written plans) is
  bad-plan amplification; the retry ladder's re-plan rung is the designed mitigation, and
  serial-first execution caps its blast radius to one task while the engine is proven.
- **Observability.** `/dashboard` can be extended to show each task's current loop phase +
  attempt count, giving the operator an at-a-glance Night Shift view (optional, low-cost).
- **Trigger-label name is unsettled.** Throughout, `ready` denotes the Night Shift *trigger*
  label; whether that is a new label or the existing `ready-for-agent` *triage* label is #63's
  open decision. Deliberately left unresolved here — the claim gate (`in-progress`) composes
  with whichever name wins.
