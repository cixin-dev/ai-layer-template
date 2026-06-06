---
id: "03"
slug: strategic-planning-skill
title: strategic-planning persona skill
type: HITL
status: ready-for-agent
blocked_by: ["02"]
prd: .agents/prds/phase-1-machinery.prd.md
covers_stories: [1, 2, 3, 4, 5, 6, 7, 8, 9, 26, 27]
---

# strategic-planning persona skill

## What to build

A main-session PM persona skill at `.claude/skills/strategic-planning/SKILL.md` that stands in
for the absent human PM (ADR-0001) and drives Phase 1's Strategic Planning. It is a **skill, not
a sub-agent** (ADR-0006): a Claude Code sub-agent runs in separate context and returns only a
summary, which cannot hold the multi-turn brain dump → clarifying-questions dialogue the role
*is*. It is a **skill, not a command** (ADR-0005): Phase 1 is interactive dialogue.

The skill:

- Carries `disable-model-invocation: true` — an interactive session must not auto-trigger.
- Adopts a **lean** PM persona: mine only the *judgment instincts* — lead with the problem not
  the solution, ask "why" repeatedly, name Non-Goals, be willing to say no, hold scope
  discipline. Drop all enterprise GTM / sprint-health / RICE / NPS / roadmap machinery from the
  source persona (ADR-0006).
- Orchestrates, in the main session: **brain dump → clarifying questions → `to-prd` →
  `to-tickets`**. It supplies the judgment layer; it calls the upstream `to-prd` for the
  mechanical PRD generation (so it is not redundant with `to-prd`), then `to-tickets` (Ticket 02)
  for decomposition.
- Carries the **Alignment checkpoint** in its brain-dump step, with a concrete escalation
  predicate (not a count): a surfaced term is captured into `CONTEXT.md` **inline** when it is
  lone, additive, and self-contained (no existing entry contradicts it, definable on its own).
  It **escalates** — via a handoff to a fresh session — to a full `grill-with-docs` Alignment
  pass when **either** (a) the term contradicts or would force a rewrite of an existing
  `CONTEXT.md` entry, **or** (b) two-or-more new terms are interdependent (defining one forces
  defining/renaming the others). This embodies the reentrant cadence: Strategic Planning runs
  once per feature and is the step that notices new language and reopens Alignment.
- Creates **no** `.claude/agents/` file.

## Acceptance criteria

- [ ] `.claude/skills/strategic-planning/SKILL.md` exists with valid frontmatter including
      `disable-model-invocation: true`.
- [ ] The skill orchestrates brain dump → clarifying questions → `to-prd` → `to-tickets`, in the
      main session, and references those skills by name.
- [ ] The persona text carries the judgment instincts (problem-first, repeated "why",
      Non-Goals, say-no, scope discipline) and none of the dropped enterprise machinery.
- [ ] The brain-dump step describes the Alignment checkpoint with the concrete predicate:
      inline-capture a lone/additive/self-contained term; escalate to a fresh-session
      `grill-with-docs` handoff when the term conflicts with an existing entry **or** ≥2 new
      terms are interdependent (conflict-or-coupling, not a count).
- [ ] No `.claude/agents/` file is created.

## Blocked by

- Ticket 02 (to-tickets fork) — the skill orchestrates `to-tickets`, so that skill must exist
  for the chain to be real.

## Notes

HITL: the mined persona judgment is the substance of this Ticket and needs a human review pass
before merge (ADR-0006). `grill-with-docs` and `to-prd` stay upstream and are merely referenced,
not vendored (ADR-0004).
