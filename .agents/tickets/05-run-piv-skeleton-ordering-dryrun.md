---
id: "05"
slug: run-piv-skeleton-ordering-dryrun
title: run-piv.sh skeleton — Ticket discovery + blocked_by ordering + --dry-run
type: AFK
status: ready-for-agent
blocked_by: []
prd: .agents/prds/piv-pipeline-automation.prd.md
covers_stories: [1, 6, 7, 15]
---

# run-piv.sh skeleton — discovery + ordering + --dry-run

## What to build

The spine of the PIV driver: a stateless bash script that discovers Tickets, orders them by
dependency, and prints what it *would* run — without yet invoking `claude` or touching code.
This is the tracer bullet: end-to-end runnable, mutates nothing.

`scripts/run-piv.sh`:

- **Discovers Tickets dynamically** — iterates `.agents/tickets/*.md`, parsing `id`,
  `slug`, and `blocked_by` from each file's frontmatter. No hardcoded list.
- **Orders by `blocked_by`** — produces a dependency-respecting (topological) order. A Ticket
  runs only after every id in its `blocked_by` is ordered before it. Detect and refuse on a
  cycle or an unknown `blocked_by` id (clear error, non-zero exit).
- **Optional id scoping** — positional args (`run-piv.sh 05 06`) narrow the run to those ids.
  Their unmet dependencies are still ordered ahead of them (or, if a dependency is itself out of
  scope and not yet at the PR gate, refuse with a clear message).
- **`--dry-run`** — prints the ordered plan as `(ticket, phase, would-run command)` triples for
  the three phases (Plan/Implement/Validate) per Ticket, in the repo's `[piv] would …` line
  style, and mutates nothing. For this Ticket, `--dry-run` is effectively the only mode that
  does anything observable; real execution arrives in Ticket 06.
- **Skeleton phase loop** — the per-Ticket Plan→Implement→Validate loop exists as a structure
  with the actual `claude -p` calls stubbed/TODO (filled in 06), so the ordering and dry-run
  plan already reflect the real phase sequence.

## Acceptance criteria

- [ ] `scripts/run-piv.sh` exists and is executable.
- [ ] Running with `--dry-run` prints the three phases per Ticket in dependency order and
      changes nothing on disk or in git.
- [ ] `blocked_by` is honored: a Ticket never appears before any id it is blocked by.
- [ ] A cycle or an unknown `blocked_by` id produces a clear error and non-zero exit.
- [ ] Positional id args scope the run; unmet in-scope dependencies are ordered ahead, and an
      out-of-scope unmet dependency is refused with a clear message.
- [ ] A self-contained `scripts/run-piv.test.sh` (no external framework — `CLAUDE.md` forbids
      stack-specific tooling) runs as `bash scripts/run-piv.test.sh`, exits non-zero on any
      failed assertion, and is this Ticket's PIV **validate gate**.
- [ ] Tests use **fixture** `.agents/tickets/` directories and assert on `--dry-run` stdout:
      (a) plain ordering with no deps; (b) `blocked_by` reordering; (c) cycle/unknown-id
      rejection; (d) id-scoping with a dependency pulled in.

## Blocked by

None — can start immediately.

## Notes

Keep the script dumb and memoryless (ADR-0008): order and state come from files, never from any
in-script accumulated state. Frontmatter parsing should be minimal bash (no YAML library —
CLAUDE.md forbids stack-specific tooling); a small `grep`/`sed` reader over the known keys is
enough since the frontmatter shape is fixed by the Ticket template.

This Ticket deliberately stops short of invoking `claude` so the ordering/dry-run logic can be
verified hermetically before any token-spending behavior exists (Ticket 06 builds on it).
