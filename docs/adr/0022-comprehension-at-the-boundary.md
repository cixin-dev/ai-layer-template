# Comprehension at the boundary: canonical docs stay English; the human layer is Traditional Chinese and ephemeral

**Status:** Accepted (2026-06-18); retroactive — born from a grill diagnosing canonical-doc
inflation (class of problem: misrouting to `grill-with-docs` as feature entry point →
canonical doc inflation → the author has no low-friction checkpoint to review and direct
their own system).
**Revised (2026-06-25):** decision #3 (CI floor) retracted as over-design. The comprehension
floor now lives at the human gate — `/validate` Phase 5 — not in CI. See "Revision" below.

## Context

The English-only rule for `CONTEXT.md` and ADRs was a deliberate, project-start design to
prevent vocabulary drift in the Ubiquitous Language. The author reads both Traditional
Chinese and English fluently — English-only is not a comprehension barrier; it is a
zero-drift guarantee, and it stays.

The problem was elsewhere. `grill-with-docs` (an upstream alignment tool) was being used as a
cold-start entry point for new feature ideas, triggering full canonical-doc rewrites on each
use. The harness affordance was wired backwards: `strategic-planning` had
`disable-model-invocation: true` (would not auto-invoke), while `grill-with-docs` had no such
guard. The compound effect: every feature idea routed through a heavy alignment session → new
terms added to canonical docs without inline confirmation → the docs grew faster than the
author could deliberately review them at change time.

Two root causes, treated asymmetrically because only one is mechanically interceptable:

- **Misrouting (A)** — `grill-with-docs` as cold-start feature entry, over-triggering
  rewrites. Fixable only in prose (`CLAUDE.md` routing rule) — there is no hook seam on which
  skill was invoked.
- **Missing comprehension floor (D)** — no checkpoint where a canonical-doc change is
  surfaced to the author in their language at the point they actually gatekeep it. The author
  is the gatekeeper of every PR; the gap was that nothing required the change to be explained
  in TC at that gate, so reviewing a canonical-doc PR was high-friction.

## Decision

1. **Vocabulary stays English** — `CONTEXT.md` and ADR prose remain English. This preserves
   zero-drift for the Ubiquitous Language. No change to the existing rule.

2. **TC comprehension lives only in ephemeral surfaces** — Traditional Chinese explanations
   exist in two places: (a) inline during `strategic-planning` (agent narrates a new term in
   TC and waits for author confirmation before writing), and (b) PR bodies. TC text is
   **never persisted into canonical files** — that would create a second drifting source of
   truth, the exact failure mode the English rule was written to prevent.

3. **Comprehension floor at the human gate** — every PR must include a `## 變更說明` section
   (Traditional Chinese, what changed and why) in the PR body. This is required by `/validate`
   Phase 5 and enforced by the author's PR review — the point where the author already
   gatekeeps every change. It is **not** a CI gate (see Revision). *(Scope broadened from
   canonical-doc PRs to every PR on 2026-06-29 — see second Revision.)*

4. **Routing contract in `CLAUDE.md`** — new feature ideas enter via `strategic-planning`
   (brain dump); `grill-with-docs` may only be invoked from a `strategic-planning` escalation
   handoff, never cold-started directly.

5. **Both fixes are prose, gatekept by the human** — the routing rule and the comprehension
   floor are both enforced by judgment at the human gate, not by a mechanical check. This is
   deliberate: the system's goal is to *reduce* human checking inside the boundary and
   *concentrate* it at the PR, where the author reviews. A canonical-doc change is exactly the
   kind of decision that warrants the author's eyes; a CI gate that merely re-checks what the
   author already reviews is redundant machinery. (It is also unenforceable here — a free-plan
   private repo cannot mark a status check as required; see auto-memory
   `free-private-repo-no-required-checks`.)

## Rejected alternatives

- **Bilingual `CONTEXT.md`** — each entry would carry an English definition and a TC
  explanation. Rejected: doubles the doc size and creates two surfaces that can drift from
  each other, which is precisely what the English rule was written to prevent.
- **`CONTEXT.zh.md` — persistent TC translation file** — rejected for the same reason: a
  second source of truth that diverges silently over time. "Ability to understand old docs at
  any time" is a capability (ask the agent to explain in TC on demand; ephemeral), not a file
  to maintain.
- **Retire the English-only rule** — rejected: loses zero-drift guarantee for the Ubiquitous
  Language. The vocabulary precision is load-bearing.
- **CI gate enforcing the `## 變更說明` floor** — *originally accepted (decision #3,
  2026-06-18), now rejected — see Revision.* A `pull_request`-only `doc_change_gate.sh` parsed
  the PR body and failed the check if the TC section was absent. Retracted: it duplicates the
  author's own review, and on a free-private repo a red check cannot block a merge anyway, so
  it was inert — it signalled an enforcement it could not deliver.

## Consequences

- The author regains comprehension at **change time** (TC PR body, required by `/validate`
  Phase 5) and **on demand** (ask the agent to explain any canonical doc in TC; ephemeral, no
  persistence).
- No second persistent translation to maintain or let drift.
- No CI machinery to keep green for a check that cannot block. The floor is a one-line prose
  requirement in `/validate` Phase 5, carried by the author's review.
- Residual risk: the routing contract, the `grill-with-docs` handoff contract, and the
  comprehension floor are all prose; an agent that ignores `CLAUDE.md` / the validate command
  can still misroute or skip the TC section. This is accepted — it matches the risk profile of
  every other prose rule in the system, and the author's PR review is the backstop.
- `strategic-planning`'s `disable-model-invocation: true` flag and whether to flip it remains
  out of scope (see plan out-of-scope item i); it may be intentional to prevent persona
  hijacking.

## Revision (2026-06-25)

The 2026-06-18 decision shipped a CI floor (`scripts/doc_change_gate.sh`, wired as a
`pull_request`-only step) and claimed it "blocks the PR if it does not" carry a `## 變更說明`
section. That claim was false: the gate was advisory, not blocking — `main` had no branch
protection (impossible on a free-plan private repo), and a second always-green `push`
check-run masked the gate-bearing run. More fundamentally, the CI gate was over-design: it
re-checks what the author already reviews at the PR. The floor belongs at the human gate, not
in CI. `doc_change_gate.sh` and its CI wiring were removed; the requirement moved to
`/validate` Phase 5. Decisions #3 and #5 above reflect the revised design; #1, #2, and #4 are
unchanged.

## Revision (2026-06-29)

The comprehension floor was scoped to PRs touching `CONTEXT.md` or `docs/adr/`. A feature PR
(#65, closing #56) merged with no `## 變更說明` — correct under the old scope, but the author
wanted comprehension in their language for *that* change too. The original scope conflated two
distinct needs: the **zero-drift bridge** (canonical docs stay English, so a TC summary is the
author's only language path into the diff) and the **comprehension floor** (the author should
understand every change they gatekeep in their own language). The first is canonical-doc
specific; the second is universal — the author is the gatekeeper of *every* PR (Context, above).

Decision #3's scope is broadened: **every** PR body must carry a `## 變更說明` section, not just
canonical-doc PRs. The `/validate` Phase 5 PR template now emits the section unconditionally.
Everything else holds: TC stays out of canonical files (#2), and the floor remains prose at the
human gate — **no** CI gate (#5). The free-private-repo unenforceability and the
re-checks-what-the-author-reviews redundancy that retracted the CI gate apply identically at the
broader scope, so broadening the floor does **not** reopen the CI-gate question.
