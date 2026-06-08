---
id: "04"
slug: readme-context-rewrite
title: README + CONTEXT.md preamble rewrite
type: AFK
status: completed
blocked_by: ["01"]
prd: .agents/prds/phase-1-machinery.prd.md
covers_stories: [23, 24, 25, 28]
---

# README + CONTEXT.md preamble rewrite

## What to build

Rewrite the two documents that still describe the old "template / install into every project"
model so they describe the global-machinery model instead (ADR-0003).

`README.md`:

- Replace the "AI Layer Template" / drop-in-template framing with the **global-machinery** model:
  this repo is the single source of project-agnostic machinery, synced to user scope.
- State the ownership split: **project-agnostic machinery** (rules, commands, skills, examples)
  lives here → global `~/.claude/`; **project-specific context** (`CONTEXT.md`, `docs/adr/`,
  `CLAUDE.md` "Project specifics", `.agents/`) stays versioned in each downstream repo.
- Replace the **Install** section (the `install.sh` copy commands) with `sync.sh` usage,
  including `--dry-run`.
- Update the **Layout** block: drop `scripts/install.sh`; add `scripts/sync.sh` and the
  `strategic-planning` skill.
- Note that `grill-with-docs`, `to-prd`, and `to-issues` are referenced upstream, not vendored
  here.

`CONTEXT.md` preamble (the intro paragraph, ~lines 5–10):

- Rewrite away from "ships this `CONTEXT.md` pre-seeded … into every new project created from
  it" to the global-machinery framing — each downstream repo keeps its own `CONTEXT.md`
  versioned with its code; this repo's machinery is synced globally.
- Leave the **Language** / glossary section entirely unchanged.

## Acceptance criteria

- [ ] `README.md` no longer presents the repo as a copy-in template and no longer documents
      `install.sh`; it documents `sync.sh` (incl. `--dry-run`) and the global-machinery +
      project-context split.
- [ ] `README.md` Layout block reflects current files (no `install.sh`; `sync.sh` and
      `strategic-planning` present).
- [ ] `CONTEXT.md` preamble describes the global-machinery model, not "ships into every new
      project"; the Language section is byte-for-byte unchanged.

## Blocked by

- Ticket 01 (sync.sh) — the README documents `sync.sh`'s real interface, so its surface
  (flags, behavior) should be settled first.

## Notes

AFK. Pure documentation reconciliation; no behavioral surface. The glossary **Language** entries
are out of scope for this Ticket — only the preamble framing changes.
