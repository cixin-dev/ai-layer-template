# The GitHub cutover completes the Issue rename (drafts not migrated)

**Status:** Completes the transition opened by ADR-0008.

ADR-0008 named the unit of work an **Issue**, flipped the glossary source of truth, and
left a deliberate, time-boxed mismatch: the permanent machinery (`CLAUDE.md`, the PIV
skills, `/plan` + `/implement`) and the `.agents/tickets/` path still said **Ticket**. It
named **one** trigger that would end the mismatch — the **GitHub cutover** — and the four
things that cutover should do in a single sweep: connect GitHub, adopt upstream `to-issues`
as the producer, migrate the local drafts to real Issues, and sweep the residual "Ticket"
wording.

**The cutover happened.** This repo is now `cixin-dev/ai-layer-template` (private). That is
the trigger ADR-0008 was waiting on, so this ADR records the sweep it authorised — with one
deliberate divergence.

**Decision:**

1. **Sweep the residual "Ticket" wording** out of the permanent machinery in one pass —
   `CLAUDE.md`, `CONTEXT.md`, the `piv-loop` and `system-evolution` skills, and the `/plan`
   + `/implement` commands now say **Issue**. The glossary/machinery mismatch ADR-0008
   booked is closed.

2. **`to-issues` is the producer.** Going forward the unit of work is a real GitHub Issue;
   `/plan` consumes a GitHub Issue (number or URL via `gh issue view`), and `/implement`
   comments back on the Issue with `gh issue comment` — comment only, never a status
   transition (that still belongs to Validate / human review).

3. **The local drafts are NOT migrated** (this is the divergence). ADR-0008 anticipated
   migrating `.agents/tickets/{NN}-{slug}.md` into real Issues at the cutover. We do not:
   those four drafts (01, 03, 04 completed; 02 withdrawn) describe **already-shipped or
   withdrawn Phase 1 work**. Re-creating them as GitHub Issues only to immediately close
   them adds noise, not history. They are frozen in place as planning history (see
   `.agents/tickets/README.md`); GitHub Issues start empty and hold **only new work** from
   Phase 2 onward.

Because the drafts are not migrated, the `.agents/tickets/` directory is **not deleted or
renamed** — its paths are referenced by the existing ADRs and reports, which are
append-only history. It survives as a read-only archive, not a live producer.

Alternatives rejected:
- **Migrate the four drafts to real Issues (ADR-0008's literal plan)** — creates four
  GitHub Issues that are closed-on-arrival; the work they describe is done, so they carry
  no actionable state, only duplication of what the local files and git history already
  record.
- **Delete `.agents/tickets/` outright** — discards planning history that ADRs and reports
  still cite, breaking those references for a cosmetic cleanup.
- **Rename `.agents/tickets/` → `.agents/issues/`** — there are no live local Issue files
  to hold (Issues live on GitHub now), so the rename would relocate frozen history and
  break inbound references for no forward benefit.

Consequence: the glossary, the machinery, and the storage model now agree — the unit is an
**Issue**, produced by `to-issues`, living on GitHub. The only remaining use of "Ticket" is
inside `.agents/tickets/` and the historical ADRs/reports that predate this sweep, which are
frozen history, not drift.
