---
description: Create a context-rich implementation plan through codebase analysis (no code)
argument-hint: <feature description | path/to/prd.md | issue number or URL>
---

# Plan

**Input**: $ARGUMENTS

This is the **Plan** phase of the [PIV Loop](../skills/piv-loop/SKILL.md). Run it in a fresh
session. The output plan file is the only thing that crosses into the Implement phase, so
it must stand on its own.

**Core principle**: PLAN ONLY — no *deliverable* code written. Produce a document rich
enough for a one-pass implementation by an agent that has never seen this conversation.
Throwaway verification probes (a spike to confirm a dependency behaves as you claim, then
discarded) are not "writing code" — they are how a finding earns the word *verified*. Run
them during planning rather than letting Implement discover the surprise.

**Order**: codebase first. The solution must fit existing patterns.

---

## Phase 1 — Parse

Determine the input and extract a feature understanding:

| Input | Action |
|-------|--------|
| `.prd.md` / `.md` file | Read it; extract the next pending phase or the feature |
| Free-form text | Use directly |
| GitHub Issue (number or URL) | Fetch with `gh issue view {N}`; treat its body as the feature |
| Blank | Use conversation context |

Capture: **Problem**, **User story** (As a … I want … so that …), **Type**
(NEW / ENHANCEMENT / REFACTOR / BUG_FIX), **Complexity** (LOW / MEDIUM / HIGH), and any
**Issue number** for later linkback.

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
- **Ground every external-behavior claim.** Any assertion that a third-party component
  (plugin, library, API) behaves a certain way when integrated — idempotent, compatible,
  side-effect-free — is an *assumption* until a probe has actually run it. Verify it now
  with a throwaway spike (register/call it, build, observe), or carry it as an explicit
  risk. Never launder reasoning-from-docs into the Summary as established fact.
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
| Issue | {#N or N/A} |

## Assumptions & Risks
List every load-bearing claim the plan rests on, especially how external/third-party
components behave when integrated. A claim is **VERIFIED** only if you ran the experiment
that proves it — cite the command and its result. Reasoning from docs or "it should…" is
**ASSUMED**; carry it as a risk with how Implement de-risks it first. Do not state an
ASSUMED claim as fact in the Summary.

| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| {e.g. "plugin X is idempotent with the existing url filter"} | {status} | {what you ran and saw, or the risk + first Implement step to confirm} |

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
- [ ] Every external-behavior claim is VERIFIED by a probe, or carried as an explicit risk
- [ ] End-to-end behavior verified
```

## Phase 5 — Output

Report: plan path, a 2–3 sentence summary, scope (files created/updated, task count), the
key patterns with `file:line`, and the next step (review, then `/implement <plan-path>` in
a fresh session).
