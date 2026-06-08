# Plan: Strategic Planning Skill

## Summary

Create `.claude/skills/strategic-planning/SKILL.md` — a lean PM persona skill that runs
in the main session and drives Phase 1's flow: brain dump → clarifying questions → `to-prd`
→ `to-issues`. The skill carries the judgment instincts of a PM (problem-first, repeated
"why", Non-Goals, say-no, scope discipline) and none of the dropped enterprise machinery
(GTM / RICE / NPS / sprints). It embeds the Alignment checkpoint: inline-capture a lone
additive term into `CONTEXT.md`; escalate to a fresh-session `grill-with-docs` handoff on
conflict-or-coupling.

## User Story

As a solo developer I want a `strategic-planning` skill that adopts a PM persona in my
main session so that I get a human PM's judgment — problem-first thinking, scope discipline,
Non-Goals — without hiring one.

## Metadata

| Field            | Value                                  |
|------------------|----------------------------------------|
| Type             | NEW                                    |
| Complexity       | LOW                                    |
| Systems affected | `.claude/skills/strategic-planning/`   |
| Ticket           | 03                                     |

## Patterns to Follow

### Frontmatter structure
```yaml
---
name: piv-loop
description: The Plan-Implement-Validate inner loop for working one ticket at a time. Use when ...
---
```
// SOURCE: .claude/skills/piv-loop/SKILL.md:1-4

The `strategic-planning` skill adds one extra field that the existing skills omit:
`disable-model-invocation: true`. This is required because the skill must not auto-trigger
— the user invokes it explicitly to start an interactive PM dialogue.

### Heading and prose structure
```markdown
# PIV Loop

Plan → Implement → Validate. The per-ticket inner loop of agentic engineering. Its defining
move is **session separation** ...

## Why session separation

...

## The three phases

**Plan** — New session. ...
→ run `/plan`.
```
// SOURCE: .claude/skills/piv-loop/SKILL.md:6-43

Pattern: H1 title → brief framing paragraph → ## sections with bolded sub-items → `→ run`
callouts for upstream skill invocations.

### Cross-skill references (prose, not metadata)
```markdown
[system-evolution](../system-evolution/SKILL.md)
```
// SOURCE: .claude/skills/piv-loop/SKILL.md:35

Upstream skills that are referenced but not vendored (`to-prd`, `to-issues`, `grill-with-docs`)
are named inline by backtick name (`` `to-prd` ``) and linked when a local path exists.
Since these live in user scope (`~/.claude/`), not in this repo, they are named without a
local link.

### "When NOT to use" tail section
```markdown
## When NOT to use

Trivial one-line changes don't need the full loop — use judgment. The ceremony pays off for
anything with real design surface or more than a couple of steps.
```
// SOURCE: .claude/skills/piv-loop/SKILL.md:45-49

Include a "When NOT to use" section as a terminating guardrail, consistent with the other
skills.

## Files to Change

| File                                                | Action | Purpose                         |
|-----------------------------------------------------|--------|---------------------------------|
| `.claude/skills/strategic-planning/SKILL.md`        | CREATE | The skill itself                |

No `.claude/agents/` file. No other files touched.

## Tasks

### Task 1: Create the strategic-planning skill

- **File**: `.claude/skills/strategic-planning/SKILL.md`
- **Action**: CREATE
- **Mirror**: `.claude/skills/piv-loop/SKILL.md:1-49`
- **Implement**: Write the file using the exact content spec below. Do not deviate.

---

**Exact content spec for `.claude/skills/strategic-planning/SKILL.md`:**

```
---
name: strategic-planning
description: PM persona skill for Phase 1. Drives brain dump → clarifying questions → PRD → Issues in the main session. Use when starting a new feature, when the user wants to turn a conversation into a PRD, or when they explicitly invoke strategic planning.
disable-model-invocation: true
---

# Strategic Planning

A lean PM persona that runs in the **main session** — not a sub-agent — to drive Phase 1:
brain dump → clarifying questions → PRD → Issues. It stands in for the absent human PM,
supplying the judgment layer that `to-prd` and `to-issues` do not: leading with the
problem, asking "why" until the need is understood, naming Non-Goals, and holding scope.

## The PM persona

Adopt these instincts for the session. Drop everything else.

- **Problem first.** Never jump to a solution before the problem is understood. Start with
  "What problem are we solving?" and resist anchoring on the user's first proposed approach.
- **Ask "why" repeatedly.** Each stated need has a deeper driver. Surface it.
- **Name Non-Goals explicitly.** The scope boundary is as important as what's in scope —
  name what the feature will *not* do and hold that line.
- **Be willing to say no.** Scope creep enters as a "nice to have." Reject additions that
  don't serve the core problem.
- **Hold scope discipline.** Shippable beats comprehensive. If the feature can't ship
  without a piece, it's in scope. Otherwise, it isn't.

Not in scope for this persona: GTM timing, sprint health, RICE scoring, NPS targets, OKRs,
roadmap positioning, or stakeholder-management ceremony.

## The flow

**1. Brain dump** — Ask the user to describe the feature, problem, or idea in whatever form
it takes. Listen for newly surfaced domain terms as they talk (see [Alignment
checkpoint](#alignment-checkpoint)).

**2. Clarifying questions** — Ask focused "why" and scoping questions until: (a) the core
problem is sharp, (b) the solution boundary is defined, and (c) the Non-Goals are named.
One question at a time; wait for the answer before the next.

**3. Generate the PRD** — Once the problem and scope are locked, invoke `to-prd` to
produce the PRD mechanically. Supply the distilled problem statement, user stories, and
Non-Goals as input.
→ run `to-prd`.

**4. Decompose into Issues** — After PRD approval, invoke `to-issues` to slice the PRD
into independently-grabbable Issues with ordering and dependencies.
→ run `to-issues`.

## Alignment checkpoint

During the brain dump, watch for domain terms that aren't yet in `CONTEXT.md`.

**Inline capture** — If the term is lone, additive, and self-contained (no existing entry
contradicts it; it can be defined without defining or renaming anything else), add it to
`CONTEXT.md` directly and continue.

**Escalate** — If **either** (a) the term would contradict or force a rewrite of an
existing `CONTEXT.md` entry, **or** (b) two or more new terms are interdependent (defining
one forces defining or renaming the others), do **not** patch inline. Instead:
1. Name the conflict or coupling to the user.
2. Emit a handoff via `handoff`.
3. In a fresh session, run `grill-with-docs` to resolve the vocabulary before returning to
   Strategic Planning.

This is the reentry trigger: Strategic Planning runs once per feature and is the step that
notices new language and reopens Alignment.

## When NOT to use

Skip this skill when the feature is already well-understood and scoped — jump straight to
`/plan`. Use it when the problem is fuzzy, the scope is open, or the user wants PM judgment
before committing to a PRD.
```

---

- **Validate**: Verify the file exists and that:
  - Frontmatter contains `name: strategic-planning`, `description:`, and `disable-model-invocation: true`
  - Body references `to-prd`, `to-issues`, `grill-with-docs`, and `handoff` by name
  - No forbidden enterprise vocabulary: "GTM timing" and "RICE" may appear only in the
    explicit exclusion sentence; nowhere else
  - No `.claude/agents/` file was created

## Validation

This project has no automated lint/type-check/test commands defined (CLAUDE.md "Verify
commands" is a placeholder). Validation is structural:

```bash
# File exists
ls .claude/skills/strategic-planning/SKILL.md

# Frontmatter check
grep -E "^disable-model-invocation: true$" .claude/skills/strategic-planning/SKILL.md

# References upstream skills
grep -E "to-prd|to-issues|grill-with-docs" .claude/skills/strategic-planning/SKILL.md

# No agents file created
ls .claude/agents/ 2>&1  # should show no strategic-planning entry
```

Human review (HITL) is required per ticket notes (ADR-0006): confirm the persona judgment
captures the correct instincts and the Alignment checkpoint predicate is faithfully expressed.

## Acceptance Criteria

- [ ] `.claude/skills/strategic-planning/SKILL.md` exists
- [ ] Frontmatter: `name: strategic-planning`, `description:`, `disable-model-invocation: true`
- [ ] Skill orchestrates brain dump → clarifying questions → `to-prd` → `to-issues` in main session
- [ ] Persona text: problem-first, repeated "why", Non-Goals, say-no, scope discipline
- [ ] No enterprise machinery (GTM / RICE / NPS / sprint-health / roadmap)
- [ ] Alignment checkpoint: inline for lone/additive term; escalate to fresh-session `grill-with-docs` on conflict-or-coupling
- [ ] Upstream skills (`to-prd`, `to-issues`, `grill-with-docs`) referenced by name, not vendored
- [ ] No `.claude/agents/` file created
- [ ] Human (HITL) review of persona judgment before merge
