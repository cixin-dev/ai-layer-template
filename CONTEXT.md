# Project Context — Glossary

The shared glossary for this project. Every term here means one thing, named one way.

This repository is a **template**: it ships this `CONTEXT.md` pre-seeded with the Harness
vocabulary (below) so that every new project created from it starts with the same language.
As a project grows, its own domain terms (e.g. `Session`, `Turn`, `Model Request` — the
words specific to what that software actually does) are added to this same file. The
filename is always `CONTEXT.md`.

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

### Phase 1 — Project Setup (project-level, once per project or feature)

The one-time, project-level work done before per-ticket coding begins. Two parts:
**Alignment** establishes shared language and records the decisions that shape the work;
**Strategic Planning** crystallises that intent into a PRD and tickets. Both run once per
project or feature — distinct from the per-ticket work of Phase 2.

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
The project-level planning stage: brain dump → clarifying questions → PRD → tickets. Runs
once per project or feature and *outputs* the tickets that Phase 2 consumes. Distinct from
PIV's Plan step, which is ticket-level and runs once per ticket. Term: Cole Medin.
_Avoid_: conflating with PIV's Plan — Strategic Planning is project-level and produces
tickets; PIV's Plan is ticket-level and consumes one.

**PM agent**:
An agent playing the product-manager role: it helps turn discussion — including
requirements gathered from a non-technical stakeholder — into a PRD and tickets during
Strategic Planning. It stands in for the human PM this project does not have.
_Avoid_: planner, architect (those name other roles/steps)

**Ticket**:
One independently-grabbable unit of work — the output of Strategic Planning and the input
to one pass of the PIV Loop. Tickets are the bridge across the two phases: Phase 1 produces
them, Phase 2 consumes them one at a time. The "user story" inside a ticket is a field of
its content, not another name for it.
_Avoid_: issue (binds to a specific tracker), story / user story (Scrum baggage, and names
a field of the ticket, not the ticket)

**PRD** (Product Requirements Document):
The document that says *what* to build and why for one feature — the output of Strategic
Planning. One PRD per feature; it decomposes into phases, each phase into tickets. It is
superseded as intent changes. (The "phase" inside a PRD is internal structure, not a
glossary term.) Not an ADR — see that entry for the boundary.
_Avoid_: spec, requirements doc, design doc

**handoff**:
A written document that transfers a task to a fresh session so the current session stays
focused. The bridge between sessions and between phases — files, never recollection, carry
the work across. Used in both phases. Term: Matt Pocock.
_Avoid_: compaction (that continues the *same* session; a handoff opens a new one)

### Phase 2 — Development (per-ticket, ongoing)

The phase that turns aligned intent into working software, one ticket at a time.

**PIV Loop**:
The per-ticket inner loop — Plan → Implement → Validate — where each phase is a fresh
session and the written plan is the only interface between Plan and Implement. The Plan step
writes a **plan file** (`.agents/plans/{name}.plan.md`) — the sole hand-off between Plan and
Implement; the Implement step writes a **report** (`.agents/reports/{name}-report.md`)
recording what was done. Neither is a standalone glossary term — they are named artifacts of
the loop's steps, not concepts with competing names. Term: Cole Medin.
_Avoid_: plan/build/test as loose synonyms

**System Evolution**:
The outer loop: when a bug slips through, fix the Harness (rules, commands, skills) so the
class of problem can't recur — not just the surface code. The fix happens in a *retroactive
session* — a fresh session that interrogates the AI Layer ("you let this reach the codebase;
what rule/command/skill/template change stops the class?") rather than patching the symptom.
Each fix compounds. Term: Cole Medin.
_Avoid_: refactor, post-mortem
