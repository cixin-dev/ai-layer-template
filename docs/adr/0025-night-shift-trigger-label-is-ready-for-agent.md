# Night Shift trigger label is the existing `ready-for-agent`; no separate label

**Status:** Accepted (2026-07-02); relates to the Night Shift PRD (`.agents/prds/piv-ralph-loop.prd.md`) and #63.

## Context

The Night Shift outer loop needs a label to identify Issues that are "ready for the agent to
pick up." Early drafts of the PRD and runbook used `ready` as shorthand, leaving open whether
the implementation would reuse the existing `ready-for-agent` label or introduce a new, more
focused one.

`gh label list` showed two labels in use: `ready-for-agent` and `in-progress`. No bare `ready`
label existed. The executor (`night_shift_run.sh`) already defaulted
`NIGHT_SHIFT_TRIGGER_LABEL=ready-for-agent` since its first implementation. The question was
whether #63 should formalize that default, create a new label, or leave the name unsettled.

The operator was consulted and confirmed: "Same — reuse ready-for-agent."

## Decision

The Night Shift trigger label **is** the existing `ready-for-agent` label. No separate `ready`
label is created or needed.

- **"Ready" in prose** (ADRs, PRD, runbook) is shorthand for `ready-for-agent`; both refer to
  the same label.
- **Deliberate staging** = not yet adding `ready-for-agent`; **deliberate release** = adding it.
  The single label already provides this capability without any new mechanism.
- The `in-progress` claim gate composes unchanged: the loop's `select_issue()` excludes any
  Issue carrying `in-progress` regardless of whether `ready-for-agent` is also present.
- `NIGHT_SHIFT_TRIGGER_LABEL` defaults to `ready-for-agent` in both the executor and the new
  outer loop; operators may override it but the canonical label name is fixed.

## Why this over the alternatives

- **Create a distinct `ready` label** — rejected: it would require creating the label,
  migrating the executor default, and dual-labelling every Issue at release time — all overhead
  with no staging benefit the existing single-label approach does not already provide
  (simplicity-first, CLAUDE.md Conventions).
- **Leave the name unsettled** — rejected: the "Trigger-label name is unsettled" bullet in the
  PRD was an open question, not a design decision; leaving it open would force every future
  reader to re-derive the answer from code.

This ADR back-defines `ready` in ADR-0023, ADR-0024, CONTEXT, and PRD prose as shorthand for
`ready-for-agent`. Those append-only ADRs need no edit; the mapping is canonical here.

## Consequences

- Every stale bare-`ready` label reference in code comments and docs is a reconciliation target
  (done in #63 Task 6).
- Operators adding an Issue to the Night Shift queue apply exactly one label: `ready-for-agent`.
- The outer loop's `select_issue()` hard-codes no label name; it reads `TRIGGER_LABEL` from
  `NIGHT_SHIFT_TRIGGER_LABEL` (DI, testable offline), defaulting to `ready-for-agent`.
- Future label renaming is a single env-var change plus a `gh label` rename; no code changes
  needed.
