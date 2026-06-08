---
description: Create a context-rich implementation plan through codebase analysis (no code)
argument-hint: <feature description | path/to/prd.md | ticket id>
---

# Plan

**Input**: $ARGUMENTS

This is the **Plan** phase of the [PIV Loop](../skills/piv-loop/SKILL.md). Run it in a fresh
session. The output plan file is the only thing that crosses into the Implement phase, so
it must stand on its own.

**Core principle**: PLAN ONLY — no code written. Produce a document rich enough for a
one-pass implementation by an agent that has never seen this conversation.

**Order**: codebase first. The solution must fit existing patterns.

---

## Phase 1 — Parse

Determine the input and extract a feature understanding:

| Input | Action |
|-------|--------|
| `.prd.md` / `.md` file | Read it; extract the next pending phase or the feature |
| Free-form text | Use directly |
| Ticket id (e.g. `01`) | Read `.agents/tickets/{NN}-{slug}.md`; treat its body as the feature |
| Blank | Use conversation context |

Capture: **Problem**, **User story** (As a … I want … so that …), **Type**
(NEW / ENHANCEMENT / REFACTOR / BUG_FIX), **Complexity** (LOW / MEDIUM / HIGH), and any
**ticket id** for later linkback.

## Phase 2 — Explore

Delegate heavy codebase research to sub-agents so the main context stays in the smart zone
(see [Smart Zone](../../CLAUDE.md#smart-zone)). Pull back only summaries. Find, with
`file:line` references:

1. Similar implementations to mirror
2. Naming conventions (real examples)
3. Error-handling patterns
4. Relevant type/interface definitions
5. Test structure and assertion style

## Phase 3 — Design

- Files to create vs. modify, and the dependency order between them.
- Risks and their mitigations.
- The success criteria that will prove the feature works (these become the validation
  strategy, not an afterthought).

## Phase 4 — Generate

Write the plan to `.agents/plans/{kebab-case-name}.plan.md`:

```markdown
# Plan: {Feature Name}

## Summary
{One paragraph: what we're building and the approach}

## User Story
As a {user} I want to {action} so that {benefit}

## Metadata
| Field | Value |
|-------|-------|
| Type | {type} |
| Complexity | {LOW/MEDIUM/HIGH} |
| Systems affected | {list} |
| Ticket | {id or N/A} |

## Patterns to Follow
{For each: a real snippet with `// SOURCE: file:lines` so Implement can mirror it.}

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `path` | CREATE/UPDATE | {why} |

## Tasks
Ordered, atomic, each independently verifiable.
### Task 1: {description}
- File: `path`
- Action: CREATE/UPDATE
- Implement: {what to do}
- Mirror: `path:lines`
- Validate: {the project's check command}

## Validation
{The project's lint / type-check / test commands, plus the end-to-end checks.}

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors
- [ ] Follows existing patterns
- [ ] End-to-end behavior verified
```

## Phase 5 — Output

Report: plan path, a 2–3 sentence summary, scope (files created/updated, task count), the
key patterns with `file:line`, and the next step (review, then `/implement <plan-path>` in
a fresh session).
