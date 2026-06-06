---
id: "08"
slug: run-piv-green-path-branch-pr-gate
title: Green path — per-Ticket branch commit + stop at PR gate + resume
type: HITL
status: ready-for-agent
blocked_by: ["07"]
prd: .agents/prds/piv-pipeline-automation.prd.md
covers_stories: [13, 14, 16]
---

# Green path — per-Ticket branch, PR gate, resume

## What to build

The success side of the loop (ADR-0008): when a Ticket goes all-green, isolate its work on a
branch and **stop at the human merge gate** — never auto-merge — and make re-runs resume
cleanly past Tickets already waiting on review.

In `scripts/run-piv.sh`:

- **All-green commit.** When all three phases pass for a Ticket, commit the Ticket's changes to
  a branch named `piv/{NN}-{slug}` (create from the current base if absent). The commit message
  references the Ticket id + slug and the PRD.
- **Stop at "PR awaiting review."** After committing, record the Ticket's state as awaiting
  review (e.g. a marker the driver can read back — a line in a state file, or branch existence +
  no merge). The driver **does not merge** and **does not open a PR on a remote** (this repo has
  no remote; "PR awaiting review" here means "branch ready, human to review/merge locally").
- **Continue independent Tickets.** A Ticket awaiting review does **not** block later Tickets
  that don't depend on it (per `blocked_by`); but a Ticket **is** blocked until every Ticket in
  its `blocked_by` has cleared the gate (merged). The driver must not build a dependent Ticket on
  top of an unreviewed dependency.
- **Resume.** Re-running the driver **skips** Tickets already at "awaiting review" or merged, so
  re-running after a human reviews/merges resumes the backlog cleanly (story 16).

Because this Ticket sets git/merge policy, it is **HITL**: the developer reviews the branch
naming, the commit granularity, and the "awaiting review" semantics before this is trusted to
run unattended.

## Acceptance criteria

- [ ] An all-green Ticket is committed to branch `piv/{NN}-{slug}`; the commit references the
      Ticket and PRD.
- [ ] The driver **never merges** and never auto-opens a remote PR; it stops at "awaiting
      review".
- [ ] A Ticket awaiting review does not block independent later Tickets, but a dependent Ticket
      is **not** started until its `blocked_by` Tickets are merged (not merely committed).
- [ ] Re-running the driver skips Tickets already awaiting review or merged (resume).
- [ ] `scripts/run-piv.test.sh` is extended (still the validate gate), using a **throwaway git
      repo** fixture + the `claude`/Verify stubs: (a) green Ticket → branch `piv/{NN}-{slug}`
      created with a commit, no merge; (b) dependent Ticket blocked until dependency merged;
      (c) independent later Ticket proceeds while another awaits review; (d) re-run skips
      awaiting-review/merged Tickets.

## Blocked by

Ticket 07 (needs the full red-path handling so the green path is the only remaining branch; the
driver must already distinguish stop-vs-proceed before it can commit-and-gate on success).

## Notes

This is the deliberate human gate of ADR-0008: the machine drives a Ticket to "green and
reviewable"; the human does the low-cost, high-leverage yes/no. Auto-merge is explicitly
rejected — the asymmetry (save one button-press vs. ship broken code straight to the base) is
not worth it.

"Merged" detection should be simple and file/git-based (e.g. the branch's commits are reachable
from the base, or a state-file flag the human/driver sets on merge). Keep it dumb and
idempotent; no remote, no tracker. If/when this repo grows a remote, opening a real PR at the
gate is a natural later extension — out of scope here.
