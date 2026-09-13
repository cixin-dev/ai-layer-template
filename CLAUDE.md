# CLAUDE.md

This file is the **AI Layer** for this project: the always-loaded contract that tells
Claude how to think, work, and verify here. Keep it lean (aim for under ~2.5k tokens); a bloated system
prompt starts every session already degraded.

Replace the bracketed placeholders with project-specific values. Delete sections that do
not apply. Do not add stack-specific tooling to this template — keep it language-agnostic
and let each project fill in its own commands.

---

## Smart Zone

LLMs have two hard limits this project is designed around — *context decay* and *amnesia*
(defined in CONTEXT.md, "Smart Zone"). The working rules that follow from them:

- **One job per session.** Plan, implement, and review are separate sessions (see
  [PIV Loop](#piv-loop)). Don't review code in the same session that wrote it — the
  reviewer would be a dumber version of the implementer.
- **Prefer `/clear` over compaction.** Clearing returns you to a known baseline. Compaction
  leaves sediment that destabilizes later behavior. Re-prime from files instead.
- **Offload research to sub-agents.** Codebase exploration can burn hundreds of thousands
  of tokens. Delegate it; pull back only the summary so the main context stays in the
  smart zone.
- **Files are the only durable memory.** The handoff between sessions is a written
  artifact (a plan, a report), never the agent's recollection.
- **Watch your own budget.** If a task is pushing you past the smart zone mid-build, write
  a checkpoint file describing remaining work and stop cleanly rather than degrading.

## PIV Loop

The per-task inner loop: **Plan → Implement → Validate**. Each phase is a *fresh session*;
the plan file is the only interface between Plan and Implement. This separation is
deliberate — it stops planning bias and context pollution from leaking into implementation.

1. **Plan** (`/plan`) — New session. Load the Issue plus the relevant slice of the
   codebase, explore (delegate heavy research to sub-agents), and emit a context-rich
   plan to `.agents/plans/{name}.plan.md`. No code is written. The plan names the exact
   `file:line` patterns to mirror, the files to change, an ordered task list, and the
   validation strategy.
2. **Implement** (`/implement`) — **Reopen a fresh session.** Read the plan, verify its
   assumptions against the real code, then execute task by task. Run the project's checks
   after every task and fix failures before moving on — never accumulate broken state.
3. **Validate** (`/validate`) — **Own fresh session.** Runs the full gate (`validate.sh` +
   the plan's E2E checklist), then hands to human review. Pass → merge. Problem →
   drop into the [System Evolution](#system-evolution) outer loop via `/retroactive`.

Anytime you find yourself prompting the same thing more than three times, promote it to a
command or skill.

## System Evolution

The outer loop. When a PIV Loop surfaces a bug or a miss, don't just patch the surface
code — treat it as a signal that the **AI Layer itself** is incomplete. Run a *retroactive
session*:

> "You let this problem reach the codebase. Look at your AI Layer — the rules, commands,
> skills, and workflow — and find what we can change so this class of problem can't recur."

Four places to look:

1. **Commands** — is the procedure itself missing a step? (e.g. a check the validate flow
   should always run)
2. **On-demand context** — do `examples/` or referenced docs need updating?
3. **Global rules** (this file) — is an existing constraint too vague to bind?
4. **Plan / PRD templates** — is a section structurally missing?

## Communication

When reporting information, be extremely concise and sacrifice grammar for the sake of concision.

## Conventions

Behavioral guardrails for every change. These bias toward caution over speed; for trivial
tasks, use judgment.

**Think before coding.** State assumptions explicitly; if uncertain, ask. If multiple
interpretations exist, surface them all — don't silently pick one. If something is unclear,
stop and name what's confusing.

**Simplicity first.** Write the minimum code that solves the problem. No speculative
features, no abstractions for single-use code, no error handling for impossible scenarios.
If 200 lines could be 50, rewrite it.

**Surgical changes.** Touch only what the task requires. Don't "improve" adjacent code or
reformat unrelated lines. Match existing style. Remove only the orphans *your* change
created; leave pre-existing dead code (mention it instead). Every changed line should trace
to the request.

**Goal-driven execution.** Turn each task into a verifiable success criterion before
starting — "add validation" becomes "write tests for invalid inputs, then make them pass."
Strong criteria let the agent loop independently; weak ones ("make it work") force constant
clarification.

**Verification-led.** Rate of feedback is your speed limit. Define how you'll verify work
*before* doing it. A claim about how a third-party or external component behaves when
integrated (idempotent, compatible, side-effect-free) is not grounded until a probe has run
it — assert it only after the experiment, never from docs or reasoning alone. A **check
command is itself such a claim** — it asserts it can distinguish pass from fail — and is
ungrounded until run against a **known-good and a known-bad** case and seen to flip **for the
right reason**. Output alone can't prove that: a known-bad can reach its *expected* result by
never executing — a broken shebang (→ rc 127) or swallowed error (`|| true`, `2>/dev/null`)
coinciding with the expected value. That flip is **forged** whether the two cases match or
differ; prove execution by asserting the known-bad's return code — don't infer it ran from
its output. Never trust or ship a GO-checklist or operator-card check that was only reasoned
about, never executed. Prefer
test-driven, vertical tracer-bullet slices (one test → one implementation → repeat) over
writing all tests up front. See
[`.claude/skills/tdd-gate/SKILL.md`](.claude/skills/tdd-gate/SKILL.md) and
[`examples/deep-module-pattern.md`](examples/deep-module-pattern.md).
Each project bundles its verify commands into `.claude/validate.sh`; the global
`validate_gate` `Stop` hook runs it automatically on session end (fails open when absent).

---

### Project specifics

Fill these in per project. Keep it short.

- **Stack**: [language, framework, key libraries]
- **Verify commands**: [the project's lint / type-check / test / build commands]
- **Architecture**: [e.g. vertical slices under `src/features/`; one folder owns a feature
  end-to-end so an agent reads one place, not every layer]
- **Do-not**:
  - Never commit directly to local `main` — main advances only by pulling merged PRs. Every change, including AI Layer / retroactive fixes to commands or this file, goes through a branch + PR. (A local-only main commit becomes a divergence after the next squash-merge — retroactive: fix-unsync-cross-mount.)
  - Never autonomously push to `main` as a side-effect of cleanup — if a worktree or branch holds commits not in main after a squash-merge, stop and surface options to the user (new branch + follow-up PR, or explicit discard). An agent that cherry-picks and pushes without asking is harder to audit than one that simply pauses. (retroactive: clean-worktree-unmerged-commits)
  - Never resolve a worktree path by scanning *forward* from a porcelain `branch` line (`grep -A2 …`), and never gate teardown on `git log main..HEAD`. The `branch` line is the last line of an entry, so forward-scan returns the *next* worktree (near-miss: deleted an unmerged tree); and squash-merge makes `main..HEAD` permanently non-empty (false "unmerged" every time). Resolve by exact match via `scripts/worktree_path.sh`; gate teardown on `{headRefOid}..HEAD` (the PR's merged tip). (retroactive: clean-worktree-wrong-worktree)
  - Never run an interactive session — above all a HEAD-mutating command (`/retroactive`, `/plan`, `/clean-worktree`, or the Night Shift orchestrator) — in a checkout where the Night Shift is live. One shared working tree makes the two actors race on `main`'s HEAD (the **HEAD race** — distinct from the already-fixed **Queue race**, the `in-progress` claim gate): the automation's `git checkout main && git pull` lands your commit on local `main`, then stacks a pushed branch over it. Per-task worktrees do **not** cover this — `/plan`, `/clean-worktree`, `/retroactive`, and the orchestrator all run in the **main checkout**, and `main` is a single exclusive integration line (git checks it out in only one worktree). Before branch work, confirm the Night Shift is quiesced: on `main`, clean tree, no extra worktrees, no in-progress `.night-shift/` loop state. The durable fix — Night Shift in its own clone — is the deferred runtime-substrate decision (`piv-ralph-loop` PRD / #61), not this rule. (retroactive: night-shift-checkout-isolation)
  - Never skip Phase 4 of `/implement` — the report is the only durable record of what shipped, and the implementer must leave the plan in `.agents/plans/` for `/validate` to read; archiving to `completed/` is Validate's job on a green gate, not the implementer's (retroactive: fix-unsync-cross-mount).
  - Never cold-start `grill-with-docs` as a feature entry point — it may only be invoked from a `strategic-planning` escalation handoff; every feature idea enters via `strategic-planning` (brain dump) first. Cold-starting `grill-with-docs` is the misrouting that inflates canonical docs silently (retroactive: comprehension-at-the-boundary).
  - Canonical docs (`CONTEXT.md`, ADRs) stay English — **never persist Chinese translations into canonical files**, which would create a second drifting source of truth (retroactive: comprehension-at-the-boundary).
  - Every PR body must include a Traditional Chinese `## 變更說明` section (what changed and why) — the author's comprehension checkpoint at the human gate. Authored by `/validate` Phase 5; carried by the author's PR review, not CI (retroactive: zh-summary-every-pr, ADR-0022).
  - Never ship a GO-checklist / operator-card check that was never executed — a check is a claim (it asserts it tells pass from fail), ungrounded until dry-run against a **known-good AND known-bad** case. #61's live probe verified the executor but left its own runbook's checks unrun: §5's `git log --reverse <branch>` walked from the root commit ("Initial commit"), never verifying "plan is the branch's first commit." (retroactive: verify-check-commands)
  - Never trust a grounding block's pasted `# → observed:` at the gate — **re-execute** it. `/validate` Phase 3.5 is the enforcement: any runbook/operator-card changed on the branch has its checks re-run (known-good + known-bad); a pasted `observed:` is unverified until reproduced. Prose forbade shipping unrun checks twice and didn't bind, so the gate re-runs rather than re-reads. #81's known-bad fake `gh` was a forged flip (see Verification-led): `62 → (empty)` looked real, but the empty came from an exec-failure (broken shebang → rc 127), not an empty queue. (retroactive: validate-reexec-operator-checks)
  - Scope of the above is checks **and launch/operational commands** — a start/cron/daemon block is in scope even with no `# → observed:` line; its *absence* is the finding. A scheduler-reentered command (a `*/5` cron that can outlast its tick) must carry its concurrency guard (`flock -n -E 0` → the HEAD race, ADR-0024) **and** a grounding block proving the guard no-ops on contention, or `/validate` Phase 3.5 FAILs the gate. The loop runbook §4 shipped an unguarded `*/5` cron precisely because a launch line read as an "example," not a "check." (retroactive: launch-command-grounding)
  - Never commit a shell script non-executable — a `*.sh` at git mode `100644` rc-126's ("Permission denied") the instant anything execs it **by path**, silently until run (`night_shift_run.sh` shipped `100644` and died this way at Night Shift launch, exec'd directly at `night_shift_loop.sh:110`). `.claude/validate.sh` now fails the gate on any tracked `*.sh` not mode `100755` (`scripts/exec_bit_check.sh`). `chmod +x` alone won't stage the bit — `core.fileMode` is `false` on the NFS checkout, so git ignores the on-disk mode; stage it with `git update-index --chmod=+x <file>`. (retroactive: script-exec-bit-gate)
  - Never search code with a bash `grep`/`rg`/`sed`/`awk` whose quoted regex carries shell-exec bytes (`| sh`, or `$(`/backtick next to `eval`/`sh -c`) — the PreToolUse security guard string-matches the whole command, quoted literals included, and false-blocks it as "opaque code execution." Use the **Grep tool** for code search (the guard never inspects non-Bash tools); the block message itself names the exact matched-token class and the `! …` escape hatch. (retroactive: search-via-grep-tool)
  - Never let a harness safeguard depend on a remembered re-run. `git pull` + `sync.sh` was the only thing keeping user-scope symlink sources and hook copies fresh; nothing triggered it for three months, so two retroactives (#95's escape hatch, notify-on-FAIL) never reached the live hooks and `strategic-planning` called skills that were not installed. `harness_freshness.sh` (SessionStart, ADR-0029) now names behind / off-branch / dirty / dangling / stale-copy state in every session — act on its lines, never dismiss them; an ADR that accepts a "narrow drift window" must name the mechanism that bounds it. "Never dismiss" binds only while every line is actionable: a gate must not fire on a state the Harness elsewhere declares expected — untracked plan drafts on `main` are `/implement`'s pickup state, and (b) fired on them from its first session — so put each declared-expected state in the gate's known-good fixture before shipping it. (retroactive: harness-freshness-gate; freshness-dirty-plan-drafts)
  - Never let a script resolve `claude` (or any operator tool) through bare PATH, and never verify a script's precondition in an interactive shell — a `.bashrc` alias is invisible to scripts and cron. `night_shift_run.sh` defaulted to `claude` → root-owned npm-global `/usr/local/bin/claude` 1.0.8, while the session alias ran `~/.claude/local/claude` 2.1.269; runbook §1(b) passed only because it ran under the alias. The executor now prefers the local install and refuses below `NIGHT_SHIFT_CLAUDE_MIN` (rc 5), `check-claude` verifies in the script's own context, and `harness_freshness.sh` (e) names a PATH/local mismatch every session. (retroactive: claude-path-floor)
  - Never write a skill or command step that reaches a `disable-model-invocation: true` skill through the Skill tool (or a bare `→ run \`name\``) — the harness refuses it ("cannot be used with Skill tool… Ask the user to run /name themselves"), so the step never fires; phrase it as "tell the user to run `/name`". And every `Call the Skill tool with "X"` in a linked skill needs X linked too — hand-picked symlinks (ADR-0007) miss shared deps: `grill-me`/`grill-with-docs`/`triage` sat broken on `grilling`/`domain-modeling` for months, and `strategic-planning` handed off to four user-invoked skills. `harness_freshness.sh` (f) names both at every session start (ADR-0030). (retroactive: skill-dep-closure)
