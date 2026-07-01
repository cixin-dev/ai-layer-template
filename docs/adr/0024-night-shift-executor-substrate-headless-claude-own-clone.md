# Night Shift executor runs headless `claude -p` phase sessions inside its own clone

**Status:** Accepted (2026-06-30); **depends on** ADR-0023 (triggers schedule, don't judge) and
the Night Shift PRD (`.agents/prds/piv-ralph-loop.prd.md`, issue #61). Leaves the PIV artifact
lifecycle (ADR-0013 plan archived by validate, ADR-0014 plan seeded as first commit) **unchanged**.

## Context

The Night Shift thin executor (`scripts/night_shift_run.sh`) drives one `ready` Issue through the
PIV Loop — `/plan` → `/implement` → `/validate` — with no human between phases. The decider already
decides *which* phase runs next from durable artifact state (ADR-0023); this decision is about the
**runtime substrate**: by what mechanism does each phase actually run, and in which working tree?

Three forces constrain the answer:

1. **Session isolation is non-negotiable.** The Smart Zone doctrine (CLAUDE.md) requires Plan,
   Implement, and Validate to each run in a *fresh* session — clean context, the project's slash
   command expanded, its hooks loaded. A long-lived loop that "keeps going" across phases is the
   naive Ralph Loop ADR-0023 rejects.
2. **The HEAD race (CLAUDE.md Do-not, `night-shift-checkout-isolation`).** `/plan`, `/implement`
   (its branch+worktree setup), `/validate`, `/clean-worktree`, and the orchestrator all touch
   `main`'s HEAD in the **main checkout**. If the automation and a human share one working tree,
   the loop's `git checkout main && git pull` lands a human commit on local `main` and stacks a
   pushed branch over it. Per-task worktrees do **not** cover this — `main` is a single exclusive
   integration line. CLAUDE.md names this and defers the durable fix ("Night Shift in its own
   clone") to *this* decision.
3. **Auth must resolve to the operator's subscription, unattended.** Spawned sessions cost real
   credits; they must run on the claude.ai login, not an unfunded API key, with no interactive
   prompt stalling the loop.

## Decision

**1. Each phase is a headless `claude -p "/<phase>"` subprocess.** One OS process per phase gives
structural fresh-session isolation for free: a new process has clean context and loads the project
slash command + hooks exactly as an interactive session would. The executor blocks on the
subprocess; its return *is* the phase-complete event. stdin is `/dev/null` (a TTY-less `claude -p`
otherwise waits ~3s on stdin). This is the only mechanism that delivers a real PIV session
non-interactively — verified in planning (`probe-echo` → `PROBE_SLASHCMD_OK`, exit 0) and gated
end-to-end by the Task 2 / Task 6 probes before any executor code is trusted.

**2. The executor runs in a dedicated Night Shift clone.** A second clone of the repo is a distinct
working tree over the same remote, so the automation's `main` and the human's `main` never alias
the same checked-out HEAD — resolving the HEAD race at its root rather than patching symptoms. The
executor's `NIGHT_SHIFT_ROOT` is that clone's main checkout; per-task worktrees are created beside
it as usual.

**3. The recurring event+poll scheduler is deferred to #63.** This slice does a single end-to-end
drive of one Issue. How the executor is *invoked repeatedly* (event channel + scheduling poll,
queue selection across many Issues, serial→N concurrency, kill switch) is a separate decision.

### Auth posture (operational precondition)

Phase sessions run on the operator's **claude.ai subscription** (`~/.claude/.credentials.json`). An
exported `ANTHROPIC_API_KEY` takes **precedence** over the login — a stale, unfunded test key was
found in the host `~/.bashrc` and produced `Credit balance is too low` until removed. Therefore: the
Night Shift host **must not export `ANTHROPIC_API_KEY`** (nor `ANTHROPIC_AUTH_TOKEN`). With the key
unset, a probe `claude -p` returned `SUBOK`, exit 0. Because the host environment is clean, the
executor needs no per-call `env -u` scrubbing.

### Other operational preconditions

- **Graduated push dial (#59, landed).** Spawned sessions inherit the operator's user-scope auto
  posture; `Bash(git push *)` is graduated `ask→allow` in the live dial. Project/local-scope
  `defaultMode:auto` is *ignored* — only user-scope settings or `--permission-mode` grant auto
  (`spike-autonomy-probes-report.md`). The deterministic dangerous-push floor (`security_guard.py`,
  ADR-0020) stays enforced independently of this graduation.

## Why this over the alternatives

- **cron** — rejected: external infrastructure, none in the repo; nothing to commit or test, and it
  does not address isolation or the HEAD race.
- **`/loop` + `/routines`** (a long-lived chained session that re-prompts itself) — rejected: that
  is one session spanning all phases, collapsing per-phase isolation — the Ralph Loop ADR-0023
  forbids. Out of scope by the PRD.
- **Workflow subagents** — rejected: a subagent is not a full PIV session; it does not expand the
  project slash command or load the session hooks, so it cannot faithfully *be* `/plan` /
  `/implement` / `/validate`.
- **Run the loop in the human's main checkout** — rejected: this is exactly the HEAD race. Force #2
  is the whole reason a dedicated clone exists.

## Consequences

- The executor stays **thin**: it knows only *how* to spawn a phase and perform a claim, never
  *whether* — every "what next" comes from the decider (ADR-0023). Substrate choice and policy stay
  cleanly separated.
- Phase isolation is enforced by the OS process boundary, not by discipline — a phase physically
  cannot leak context into the next.
- The clone is an **operational prerequisite**, not code: provisioning it (and keeping
  `ANTHROPIC_API_KEY` unexported) is a host-setup step the executor assumes. A future change that
  runs the loop in a shared checkout is a *reversal* of this ADR and must be recorded as a
  superseding one.
- Reusing `claude -p` means the loop inherits every future improvement to the slash commands and
  hooks with no executor change — the substrate is the product itself, not a reimplementation.
- The recurring-invocation substrate (#63) builds on this one; it does not revisit isolation, the
  clone, or the auth posture.
