# Comprehension at the boundary: canonical docs stay English; the human layer is Traditional Chinese and ephemeral

**Status:** Accepted (2026-06-18); retroactive — born from a grill diagnosing author
comprehension loss (class of problem: misrouting to `grill-with-docs` as feature entry
point → canonical doc inflation → author loses ability to read and direct their own system).

## Context

The English-only rule for `CONTEXT.md` and ADRs was designed to prevent vocabulary drift.
It achieved that goal — but was over-applied: **all** prose in canonical files became
English, including explanatory text that only the TC-native author would ever read. At the
same time, `grill-with-docs` (an upstream alignment tool) was being used as a cold-start
entry point for new feature ideas, triggering full canonical doc rewrites on each use. The
harness affordance was wired backwards: `strategic-planning` had
`disable-model-invocation: true` (would not auto-invoke), while `grill-with-docs` had no
such guard.

The compound effect: every feature idea routed through a heavy alignment session → new
terms added without inline confirmation → canonical docs expanded in English the author
could not fully parse → the author was demoted from *author* to *reviewer who can't read
the document*.

Two root causes, treated asymmetrically because only one is mechanically enforceable:

- **Misrouting (A)** — `grill-with-docs` as cold-start feature entry, over-triggering
  rewrites. Fixable only in prose (`CLAUDE.md` routing rule) — there is no hook seam on
  which skill was invoked.
- **Missing comprehension floor (D)** — no checkpoint where changes are explained to the
  author in their language before being committed. Partially mechanizable: a CI gate can
  require a TC explanation section in every PR that touches canonical docs.

## Decision

1. **Vocabulary stays English** — `CONTEXT.md` and ADR prose remain English. This
   preserves zero-drift for the Ubiquitous Language. No change to the existing rule.

2. **TC comprehension lives only in ephemeral surfaces** — Traditional Chinese explanations
   exist in two places: (a) inline during `strategic-planning` (agent narrates a new term
   in TC and waits for author confirmation before writing), and (b) PR bodies. TC text is
   **never persisted into canonical files** — that would create a second drifting source of
   truth, the exact failure mode the English rule was written to prevent.

3. **CI floor for canonical doc PRs** — any PR that touches `CONTEXT.md` or `docs/adr/`
   must include a `## 變更說明` section (Traditional Chinese) in the PR body. Enforced by
   `scripts/doc_change_gate.sh`, run as a standalone `pull_request`-only **job**
   (`doc-gate`) in CI. A standalone job (not a step inside the `test` job) gives the gate
   its own status check that a push-event run cannot mask — but a check only *blocks* a
   merge once it is marked **required** in branch protection (see Consequences).

4. **Routing contract in `CLAUDE.md`** — new feature ideas enter via `strategic-planning`
   (brain dump); `grill-with-docs` may only be invoked from a `strategic-planning`
   escalation handoff, never cold-started directly.

5. **Asymmetric enforcement** — the CI floor is deterministic (mechanical); the routing
   rule is prose-only (no hook can intercept which skill fires). This mirrors the existing
   `validate gate` (mechanical floor) + `tdd-gate` (semantic discipline) split documented
   in ADR-0009.

## Rejected alternatives

- **Bilingual `CONTEXT.md`** — each entry would carry an English definition and a TC
  explanation. Rejected: doubles the doc size and creates two surfaces that can drift from
  each other, which is precisely what the English rule was written to prevent.
- **`CONTEXT.zh.md` — persistent TC translation file** — rejected for the same reason: a
  second source of truth that diverges silently over time. "Ability to understand old docs
  at any time" is a capability (ask the agent to explain in TC on demand; ephemeral), not a
  file to maintain.
- **Retire the English-only rule** — rejected: loses zero-drift guarantee for the
  Ubiquitous Language. The vocabulary precision is load-bearing.
- **Prose-only for both fixes, add CI gate later if it recurs** — rejected: prose decay is
  a *proven* failure mode (it is what caused this ADR). Simplicity-first does not apply
  when the failure mode has already been demonstrated; the gate is the minimal reliable fix.

## Consequences

- The author regains comprehension at **change time** (TC PR body, required by CI) and
  **on demand** (ask the agent to explain any canonical doc in TC; ephemeral, no
  persistence).
- No second persistent translation to maintain or let drift.
- The CI gate dogfoods itself: this PR touches `docs/adr/0022`, so its own body must
  contain a `## 變更說明` section. The gate blocks the PR **only when the `doc-gate` check
  is a required status check in branch protection** — a CI step that merely exits non-zero
  produces a red mark but does not stop a merge by itself. Making `doc-gate` required (and
  keeping it a standalone, push-unmaskable job) is what gives the floor teeth; without it
  the gate is advisory (inert). (retroactive: inert-doc-gate)
- **Plan constraint (this repo):** the repo is a free-plan *private* repo, where GitHub
  disables required status checks entirely (branch-protection and rulesets APIs both return
  `403 Upgrade to GitHub Pro or make this repository public`). So `doc-gate` cannot be made
  required here until the repo goes public or onto Pro. Until then the floor is two
  non-blocking signals: (a) the visible red `doc-gate` mark on the PR, and (b) a local
  validate-time reminder (`scripts/doc_change_reminder.sh`, run by `validate.sh`) that fires
  in-session when the branch touches `CONTEXT.md`/`docs/adr/`, before the PR is opened. The
  reminder cannot read the PR body locally, so it reminds rather than blocks.
- Residual risk: the routing contract and the `grill-with-docs` handoff contract are prose;
  an agent that ignores `CLAUDE.md` can still misroute. This is accepted — it matches the
  risk profile of every other prose rule in the system.
- `strategic-planning`'s `disable-model-invocation: true` flag and whether to flip it
  remains out of scope (see plan out-of-scope item i); it may be intentional to prevent
  persona hijacking.
