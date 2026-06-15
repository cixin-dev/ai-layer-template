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
The automatic enforcement floor of the Validate step: a `Stop` hook (`validate_gate.py`) that
runs the project's `.claude/validate.sh` when a session tries to end and *blocks* completion on
failure — turning the test-first discipline from a norm into an enforced gate. Global machinery
(synced to `~/.claude/`), opt-in per project by the presence of `.claude/validate.sh` (fails
open when absent). One "validate" root, two layers: the **validate gate** is the *automatic
floor*; **`/validate`** is the *deliberate full pass* (`validate.sh` + the plan's E2E + the entry
to human review), run as the Validate step's own session. Framing: Cole Medin, who names both
layers with the single root "validate". The `.claude/validate.sh` indirection is this template's
language-agnostic extension of Cole's hardcoded hook (ADR-0009).
_Avoid_: "verify" as a second layer — there is no verify-vs-validate split (a false distinction;
"verify" survives only in CLAUDE.md's `Verify commands` slot, naming the commands you check
*with*, which `validate.sh` bundles); conflating the validate gate (automatic hook) with
`/validate` (deliberate command); tdd-gate (the red-green discipline the gate enforces, not the
gate itself).

**System Evolution**:
The outer loop: when a bug slips through, fix the Harness (rules, commands, skills) so the
class of problem can't recur — not just the surface code. The fix happens in a *retroactive
session* — a fresh session that interrogates the AI Layer ("you let this reach the codebase;
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

**sandbox**:
The pairing of a **worktree** (isolation container) **with** the synced auto-approve posture
(`defaultMode: auto` — a safety-classifier model judges each action by intent) that lets its
internal operations — read / search / test / edit / commit — run without per-tool-use prompts.
Safety comes from the **boundary**, not the directory wall: the validate gate guards session-end
and irreversible or untrusted operations (`git push`, recursive delete, fetch-and-execute) are
separately gated. The classifier is the *probabilistic* inner layer; the deterministic floor lives
at the boundary (the validate gate, the `security_guard.py` deny hook).
**Asymmetric by construction**: the posture is synced at *user scope* (global), so it outlives
any single worktree and applies even where no worktree container and no validate gate exist —
that "posture without container" zone is the *accepted residual risk*, held only by
`git push: ask` and `security_guard.py`.
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
The line a sandbox's *outputs* must cross to become durable or irreversible — where
verification moves from "trust the inside" to "gate the crossing". Two kinds of crossing are
gated: session-end (the validate gate must be green) and irreversible side effects
(`git push` on `ask`; recursive deletes and untrusted fetch-and-execute denied by
`security_guard.py`). Actual data *exfiltration* is explicitly out of this hook's scope.
Graduating `git push` from `ask` to `allow` is the single dial that opens the last boundary.
_Avoid_: perimeter, firewall (those imply keeping things out; the boundary gates what the
sandbox sends out).
