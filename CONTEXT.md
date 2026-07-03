# Project Context — Glossary

The shared glossary for this project. Every term here means one thing, named one way.

This repository is the **single source of project-agnostic harness machinery** — synced
to user scope (`~/.claude/`), not copied into each project. Each downstream repo keeps its own
`CONTEXT.md` versioned with its code; that file is where the repo's domain terms (e.g.
`Session`, `Turn`, `Model Request`) accumulate as the project grows. This copy captures the
machinery's own Ubiquitous Language — the terms that name the harness concepts themselves.
The filename is always `CONTEXT.md`.

## Language

**Harness**:
Everything besides the model that lets a coding agent reliably finish work in a project —
the deliberately engineered, continuously iterated scaffolding (rules, commands, skills,
examples, hooks, sub-agents, context policies, feedback loops). `Coding agent = Model +
Harness`. This is the thing this repository builds. Borrowed framing: Cole Medin / Addy
Osmani ("Harness Engineering").
_Avoid_: framework, wrapper, boilerplate

**AI Layer**:
The user-authored, version-controlled document asset at the core of the Harness:
`CLAUDE.md` + `.claude/commands/` + `.claude/skills/` + `examples/`. A subset of the
Harness — the part you write and review in PRs, not the runtime machinery around it.
Borrowed term: Cole Medin.
_Avoid_: using "AI Layer" and "Harness" interchangeably — the AI Layer is a part of the
Harness, not the whole thing.

**Smart Zone**:
The span of a session — roughly the first ~100k tokens — in which an agent still does its
best work, before attention overloads and decisions get sloppy (the *dumb zone* beyond it).
A larger context window does not extend it. The whole Harness is shaped to keep work inside
this zone: one job per session, `/clear` over compaction, research offloaded to sub-agents.
Coined here; the underlying limits are *context decay* and *amnesia* (nothing survives a
session but what is written to a file).
_Avoid_: context window (a capacity; the Smart Zone is a quality-of-attention span within it)

### Phase 1 — Project Setup (project-level)

The project-level work done before per-Issue coding begins. Two parts on **different
cadences**: **Alignment** establishes shared language and records the decisions that shape
the work — run in full at a project's birth, then **re-entered whenever new terms surface**
(ongoing); **Strategic Planning** crystallises intent into a PRD and Issues — **once per
feature**. In steady state a feature enters Phase 1 through Strategic Planning, not
Alignment; Strategic Planning is what notices new language and reopens Alignment. Distinct
from the per-Issue work of Phase 2.

**Ubiquitous Language**:
The single language shared by domain expert, developer, and code to describe the system.
Establishing it is the goal of Alignment; it is persisted in `CONTEXT.md`. Source: Eric
Evans (Domain-Driven Design), via Matt Pocock.
_Avoid_: jargon, glossary (the *concept* is Ubiquitous Language; `CONTEXT.md` is the file
it lives in)

**grill-with-docs**:
A relentless interview session that reads `CONTEXT.md` and the ADRs, challenges fuzzy or
conflicting terms as they come up, and updates those documents inline as decisions
crystallise. The method for reaching Ubiquitous Language when a codebase exists. Term:
Matt Pocock.
_Avoid_: grill-me (that is the codebase-free variant — interview to decision, no docs to
read or update)

**ADR** (Architecture Decision Record):
A short markdown note recording a decision that is both hard to reverse and surprising
without context — *why one decision* was made the way it was. Lives in `docs/adr/`. The ADRs
form a cumulative, append-only history: an ADR is superseded by a later one, never
overwritten — unlike a PRD, which states *what* to build and is replaced as intent changes.
Together with `CONTEXT.md` it is the agent's durable memory across sessions. Term: widely
used; adopted via Matt Pocock.
_Avoid_: design doc, RFC, PRD

**Strategic Planning**:
The project-level planning stage: brain dump → clarifying questions → PRD → Issues. Runs
**once per feature** and *outputs* the Issues that Phase 2 consumes. Its brain-dump step
carries an **Alignment checkpoint**: a lone, additive new term is captured into `CONTEXT.md`
inline, and only a *conflicting or coupled* term-knot escalates — via a handoff to a fresh
session — to a full grill-with-docs Alignment pass. Distinct from PIV's Plan step, which is
Issue-level and runs once per Issue. Term: Cole Medin.
_Avoid_: conflating with PIV's Plan — Strategic Planning is project-level and produces
Issues; PIV's Plan is Issue-level and consumes one.

**PM agent**:
The product-manager *role*, played by the main session adopting a PM persona (the
`strategic-planning` skill) — **not** a Claude Code sub-agent. It turns discussion,
including requirements gathered from a non-technical stakeholder, into a PRD and Issues
during Strategic Planning, standing in for the human PM this project does not have. It runs
in the main session because the work is an interactive brain dump → clarifying-questions
dialogue, which a separate-context, summary-returning sub-agent cannot hold (see ADR-0006).
_Avoid_: sub-agent (runs in its own context, can't conduct the interactive dialogue);
planner, architect (those name other roles/steps)

**Issue**:
One independently-grabbable unit of work — the output of Strategic Planning and the input
to one pass of the PIV Loop. Issues are the bridge across the two phases: Phase 1 produces
them, Phase 2 consumes them one at a time. The implementer agent's intake source is a
**GitHub Issue** — the unit is named for what it natively is, not for a tracker-independent
abstraction (ADR-0008 reverses the earlier "Ticket" framing: tracker-independence is
over-engineering for a solo, GitHub-bound project). Issues are produced by `to-issues` and
live on GitHub; `/plan` consumes exactly one (by number or URL), with ordering and
dependencies expressed as GitHub Issue links (`Blocked by #NN`). The "user story" inside an
Issue is a field of its content, not another name for it. (Pre-GitHub, an Issue was drafted
as a local file under `.agents/tickets/`; the GitHub cutover retired that crutch — see
ADR-0011. Those drafts are frozen as planning history, not migrated.)
_Avoid_: Ticket (the tracker-independence it bought is over-engineering here — ADR-0008;
the residual "Ticket" wording was swept at the GitHub cutover (ADR-0011) and now survives
only in the frozen `.agents/tickets/` archive and historical ADRs/reports, not as a licence
for new use); Jira (a different specific tracker; this project is on GitHub); "story" /
"user story" as a *name for this unit of work* — the unit is an **Issue** (Scrum baggage).
Boundary: "User Stories" remains legal as a PRD source-section and `covers_stories` as an
Issue field — those name a field/source, not the unit.

**PRD** (Product Requirements Document):
The document that says *what* to build and why for one feature — the output of Strategic
Planning, written to `.agents/prds/{name}.prd.md`. One PRD per feature; it decomposes into
phases, each phase into Issues. It is superseded as intent changes. (The "phase" inside a
PRD is internal structure, not a glossary term.) Not an ADR — see that entry for the
boundary.
_Avoid_: spec, requirements doc, design doc

**handoff**:
A written document that transfers a task to a fresh session so the current session stays
focused. The bridge between sessions and between phases — files, never recollection, carry
the work across. Used in both phases. Term: Matt Pocock.
_Avoid_: compaction (that continues the *same* session; a handoff opens a new one)

### Phase 2 — Development (per-Issue, ongoing)

The phase that turns aligned intent into working software, one Issue at a time.

**PIV Loop**:
The per-Issue inner loop — Plan → Implement → Validate — where each phase is a fresh
session and the written plan is the only interface between Plan and Implement. The Plan step
writes a **plan file** (`.agents/plans/{name}.plan.md`) — the sole hand-off between Plan and
Implement; the Implement step writes a **report** (`.agents/reports/{name}-report.md`)
recording what was done. The **Validate** step then runs in its own fresh session — `/validate`
runs the full gate plus the plan's E2E and hands to human review (pass → merge); separately the
**validate gate** `Stop` hook enforces a green floor automatically at every session-end. Neither
the plan file nor the report is a standalone glossary term — they are named artifacts of the
loop's steps, not concepts with competing names. Term: Cole Medin.
_Avoid_: plan/build/test as loose synonyms

**validate gate**:
The automatic enforcement floor of the Validate step — a `Stop` hook (`validate_gate.py`) that
runs the project's `.claude/validate.sh` when a session tries to end and *blocks* completion on
failure, turning the test-first discipline from a norm into an enforced gate. One "validate"
root, two layers: the validate gate is the *automatic floor*; **`/validate`** is the *deliberate
full pass* run as the Validate step's own session (ADR-0009).
_Avoid_: "verify" as a second layer (no verify-vs-validate split; "verify" survives only in
CLAUDE.md's `Verify commands` slot, naming the commands `validate.sh` bundles); conflating the
validate gate (automatic hook) with `/validate` (deliberate command); tdd-gate (the red-green
discipline the gate enforces, not the gate itself).

**System Evolution**:
The outer loop: when a bug slips through, fix the Harness — first the deterministic gate (a
check in `validate.sh` / the test suite), else its prose surface (rules, commands, skills) —
so the class of problem can't recur, not just the surface code. The fix happens in a *retroactive
session* — a fresh session that interrogates the Harness ("you let this reach the codebase;
what rule/command/skill/template change stops the class?") rather than patching the symptom.
Two layers, kept distinct: the **trigger** is mechanical and frequent — the workflow routes
into `/retroactive` (PIV's Validate hands a *problem* off; a session that fixes a bug already
in the codebase ends the same way), never relying on the agent remembering; the **decision**
to actually run one stays judgment (severity × recurrence). Each fix compounds. Term: Cole
Medin.
_Avoid_: refactor, post-mortem; a lifecycle hook (e.g. `SessionEnd`) as the trigger — the
trigger is a semantic event a mechanical hook can't judge (hooks enforce objective red/green
floors, handoffs carry semantic flow).

### Unattended Autonomy

The posture that lets N parallel agents run without per-tool-use approval: verify *outputs*
at the boundary (the validate gate) rather than *inputs* (each tool call).

The posture ships as a versioned, inert `.claude/settings.shared.json` that Claude Code does
*not* auto-load; `sync.sh` additively merges it into live user-scope `~/.claude/settings.json`.
- **Auto-approved**: the whole sandbox-internal toolchain — read / search / test / edit /
  commit — via `permissions.defaultMode: auto`, with **no** hand-filled allowlist. The
  safety-classifier model judges each action by intent; the absence of an allowlist *is* the
  design (ADR-0018).
- **Gated**: `git push` stays on `ask` — the single human checkpoint at the **boundary**;
  **opaque code execution** is denied by `security_guard.py`; session-end is held by the
  validate gate.
- **Why**: verify *outputs* at the boundary, not *inputs* at each call. The classifier is the
  probabilistic inner layer; the deterministic floor lives at the boundary — the validate gate
  and the `security_guard.py` deny hook (ADR-0018, ADR-0020).
- **Graduation** is the single dial (`ask` → `allow` for `git push`). The sync is
  graduation-aware: it never re-adds a shared `ask` entry the live `allow` already covers, so a
  resync can't silently spring the dial back (ADR-0017). Graduating `git push` is gated behind
  the deterministic **dangerous push** floor in `security_guard.py` (ADR-0020 / Issue #36),
  which must hold the force/main-push cases the auto-mode classifier was probe-shown to approve.

**sandbox**:
A **worktree** (isolation container) paired **with** the synced auto-approve posture
(`defaultMode: auto` — a safety-classifier model judges each action by intent) so its internal
ops — read / search / test / edit / commit — run without per-tool-use prompts. Safety is the
**boundary** gate, not the directory wall (ADR-0018, ADR-0020).
_Avoid_: treating sandbox ≡ worktree (the worktree is only the isolation half; the posture is
the other half and is broader than it); "sandbox" as a directory or VM (the protection is the
boundary gate, not isolation).

**worktree**:
The git-worktree isolation directory that is the **sandbox**'s container half — it gives
parallel agents file-level isolation from each other and from the main checkout. It is the
*container* component of a sandbox, not the whole sandbox; the auto-approve posture layered on
top (and synced globally) is the other half.
_Avoid_: using "worktree" and "sandbox" interchangeably (worktree = isolation only); branch,
clone (a worktree shares the repo's object store; it is neither).

**boundary**:
The line a sandbox's *outputs* must cross to become durable or irreversible — where verification
moves from "trust the inside" to "gate the crossing": session-end held by the validate gate,
irreversible side effects gated by `security_guard.py` (ADR-0009, ADR-0018).
_Avoid_: perimeter, firewall (those imply keeping things out; the boundary gates what the
sandbox sends out).

**opaque code execution**:
A command `security_guard.py` denies at the **boundary**: one whose real payload is **not literal
in the command**, so no human sees what will run when it is authored — via **pipe-to-shell**
(`curl … | sh`) or **command substitution into a shell** (`eval "$(…)"`). The threat is the
*opacity*, not the fetch; bare local substitution is denied too. Distinct from `exfiltration`
(data going *out*, out of scope) (ADR-0019).
_Avoid_: fetch-and-execute (names only the network-fetch source; under-describes the class and
mislabels the local-substitution denials — superseded by this term); remote code execution
(implies a remote attacker/foothold, not the local-opacity framing here).

**dangerous push**:
The subset of `git push` **denied** at the **boundary** — two forms: **force-push** (rewriting
published history) and **push-to-default-branch** (clobbering `main`/`master`) — distinct from the
benign `git push` merely gated on `ask`. Benign push is a *friction dial* (`ask → allow`);
dangerous push is a *deterministic floor* in **every** permission mode, living in the
`security_guard.py` deny hook, **not** the permission layer (ADR-0020).
_Avoid_: conflating with the benign `git push` checkpoint (that is the dial on `ask`; this is the
floor on `deny` — they graduate independently); treating the auto-mode classifier as the floor (it
is the probabilistic inner layer, not the deterministic one — ADR-0020).

**notification**:
The boundary's **outbound signal to the operator** — the complement to the validate gate
(**polling → interrupt**: a boundary event interrupts the operator so they stop polling the
`dashboard` *by hand* — the "polling" retired here is the **human's** status-checking habit).
One primitive (`notify.sh`) owns delivery; described on two axes — **transport**
(*where*: the at-keyboard **tmux bell** and the AFK **network push**) and **source** (*what event*:
**Source A** = the validate verdict, **Source B** = the PR-state watcher). A source reuses the
transports; **adding a source must not touch a transport** (ADR-0021).
_Avoid_: conflating transport and source (transport = delivery mechanism, source = triggering
event — Source B reuses both transports); "sink" / "channel" (the pre-canonical names; Issue
#40's "Channel A" is Source A); alert, ping; reading the retired "polling" as the Night Shift's
**scheduling poll** (a *machine* backstop, not the human habit interrupt replaced).

### Night Shift

The posture above **Unattended Autonomy**: where Unattended Autonomy removed *input* friction (no
per-tool-use approval inside the sandbox), the Night Shift removes *orchestration* friction (no
per-phase human initiation). It drives each `ready-for-agent`-labelled **Issue** (the trigger
label — #63/ADR-0025) through the whole **PIV Loop** — Plan → Implement → Validate — with no human
between phases, then opens a PR and stops, so a queue of `ready-for-agent` work drains itself
overnight. Its load-bearing property is that **each phase runs in its own fresh, isolated session**:
the loop automates the human's "open a new session and type the next command," and never chains
phases in one long context — that would forfeit session isolation and rot the context (see **Ralph
Loop**). The human keeps both bookends — the **Day Shift** loads the queue, the **boundary gate**
reviews the PR. The loop advances by a **synchronous zero-idle drain** on the happy path (each
finished phase returns and the loop re-selects the next work at once, in one process — not an
async event); a **scheduling poll** — a periodic machine sweep (*not* a human's
dashboard-checking) — is the backstop that discovers newly `ready-for-agent` Issues and keeps the
loop live (its runtime substrate is ADR-0026's shell drain+poll loop; the loop's triggers
*schedule* phases but never *judge* completion — ADR-0023).
_Avoid_: "PIV Ralph Loop" (the PRD title — a descriptive label, not the canonical name);
conflating with **Unattended Autonomy** (the layer below — that gates *inputs*; the Night Shift
removes *orchestration*); a single long `/loop` session chaining phases (a naive **Ralph Loop**, no
isolation).

**Day Shift**:
The human-attended planning input that loads the Night Shift's queue: write an **Issue** and add the
`ready-for-agent` label (the trigger label — #63/ADR-0025). The front bookend only; the back
bookend (reviewing the PR) is the **boundary gate**, not the Day Shift.
_Avoid_: stretching it to cover PR review (that is the **boundary gate**); reading it as a clock —
it names the human's queue-loading work, not a time of day.

**Ralph Loop**:
The borrowed brute-force technique this project is contrasted *against* — run an agent in a
`while`-loop that re-feeds the same prompt, letting it recover state from the filesystem and git
and make incremental progress each pass. Its defining property: the **whole run shares one
long-lived context — no session isolation between steps** — so attention rots as the loop grinds
on. State-in-files, not state-in-memory; named after Ralph Wiggum (brute force, not cleverness).
Term: Geoffrey Huntley ("Ralph").
_Avoid_: equating it with the **Night Shift** — the Night Shift is a Ralph Loop that *keeps*
per-phase session isolation, the one thing naive Ralph throws away; "PIV Ralph Loop" (the PRD
title) is a descriptive label for our variant, not a third name for the Night Shift.
