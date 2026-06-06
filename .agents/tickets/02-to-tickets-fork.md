---
id: "02"
slug: to-tickets-fork
title: to-tickets skill (fork of to-issues)
type: AFK
status: ready-for-agent
blocked_by: []
prd: .agents/prds/phase-1-machinery.prd.md
covers_stories: [10, 11, 12, 13, 14, 15]
---

# to-tickets skill (fork of to-issues)

## What to build

Fork upstream `to-issues` into this repo as `.claude/skills/to-tickets/SKILL.md`. The fork
exists for exactly one reason (ADR-0004): `to-issues`' output writes "issue / story / Jira",
vocabulary `CONTEXT.md` forbids. So this is a vocabulary-and-output fork, not a logic rewrite.

Keep from upstream, unchanged:

- Tracer-bullet **vertical-slice** decomposition (thin slices through all layers).
- **HITL / AFK** typing of slices; prefer AFK.
- Presenting the proposed breakdown for approval before writing anything.
- **Dependency-ordered** production so blockers are referable.

Change for this project:

- **Vocabulary becomes `Ticket` throughout** — no "issue", "story", or "Jira" anywhere in the
  skill text or its output template.
- **Output is one file per Ticket** at `.agents/tickets/{NN}-{slug}.md` — not a tracker API
  call. This repo has no external tracker.
- **Dependencies are `blocked_by: [...]` frontmatter** in each Ticket file — not tracker links.
  There is no separate index; ordering lives in the files.
- Ticket file shape mirrors the files this very PRD was decomposed into (frontmatter:
  `id`, `slug`, `title`, `type`, `status`, `blocked_by`, `prd`, `covers_stories`; body:
  What to build / Acceptance criteria / Blocked by / Notes).
- **Numbering & overwrite (the fork owns what the tracker gave upstream for free).** `NN`
  continues from the **highest existing number** in `.agents/tickets/` — a second feature's
  Tickets become `05`, `06`… and coexist in the flat dir (disk-unit = work-unit, no index).
  Assign `NN` **before** writing, in dependency order (blockers first), so `blocked_by` can
  reference real ids — the same ordering `to-issues` used to reference tracker ids. **Never
  overwrite** an existing Ticket file: on a filename collision, refuse and warn — a
  re-decomposition is an explicit human delete-then-regenerate, so hand-edits are never
  silently destroyed.

## Acceptance criteria

- [ ] `.claude/skills/to-tickets/SKILL.md` exists with valid frontmatter (`name: to-tickets`,
      a `description`).
- [ ] Glossary gate: the skill text and its output template contain **no** occurrence of
      `issue` or `Jira`, and never use `story` as a name for the unit of work (that unit is a
      **Ticket**). "User Stories" as a PRD source-section and `covers_stories` as a Ticket
      field remain legal — the gate targets the unit-name, not the field/source (see
      `CONTEXT.md` Ticket entry `_Avoid_`).
- [ ] The skill writes Tickets to `.agents/tickets/{NN}-{slug}.md`, one file per Ticket, with
      `blocked_by` frontmatter for dependencies.
- [ ] The skill retains tracer-bullet slicing, HITL/AFK typing, the approval step, and
      dependency-ordered output.
- [ ] `NN` continues from the highest existing Ticket number (features coexist in the flat
      dir); the skill never overwrites an existing Ticket file (refuse + warn on collision).

## Blocked by

None - can start immediately.

## Notes

Independent of Ticket 01. Once `to-tickets` exists, a subsequent `sync.sh` run will remove the
superseded `to-issues` upstream symlink (ADR-0004) — a consequence, not a blocker. Validation is
structural (frontmatter, reference resolution) plus the glossary gate; there is no behavioral
test for a prose skill.
