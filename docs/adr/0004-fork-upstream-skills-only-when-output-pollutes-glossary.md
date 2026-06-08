# Fork upstream skills only when their output pollutes the glossary

**Status:** Superseded by ADR-0008 — its worked example (fork `to-issues` → `to-tickets`) is
retired: the unit of work is natively a GitHub Issue, and upstream `to-issues` is kept, not
forked. The general principle below (fork only on glossary pollution) still stands; only the
`to-issues` application is reversed.

ADR-0003 makes this repository the single source of its harness machinery, synced to user
scope (`~/.claude/`). But the developer also installs **upstream** skills globally through
their authors' own installers (Matt Pocock's skills via his script; possibly others later).
So `~/.claude/` holds **both** this repo's machinery **and** coexisting upstream skills. This
ADR settles what this repo vendors versus what it leaves upstream.

**Decision:** this repo owns only its machinery **delta**, not a vendored copy of every skill
in the workflow. An upstream skill that already does the job **stays upstream and is merely
referenced**. This repo forks an upstream skill into its own `.claude/` — and removes/replaces
the upstream copy in `~/.claude/` — **only when that skill's output artifacts would write
vocabulary that violates this project's `CONTEXT.md` glossary.**

The trigger is "the output pollutes the glossary," not "we would like to own it." This keeps
the fork surface minimal and divergence from upstream low, while guaranteeing that downstream
repos never receive glossary-violating artifacts.

Applied to the Phase 1 pipeline:

- `grill-with-docs` and `to-prd` produce `CONTEXT.md` / ADRs / PRDs — already
  glossary-consistent → **stay upstream, not vendored**, just referenced.
- `to-issues` produces "issue / story / Jira" — violates `CONTEXT.md` (`_Avoid_: issue,
  story`) → **fork into this repo as `to-tickets`** (Ticket vocabulary), and **remove the
  upstream `to-issues` symlink** so no competing, polluting producer remains in user scope.

This also fixes how forking and removal relate: coexistence is the default for upstream skills
with no glossary conflict; the moment a skill's output would violate the glossary, this repo's
fork **replaces** it rather than coexisting with it.

Alternatives rejected:
- **Vendor the whole pipeline into this repo**: maximal "single source," but needless
  divergence and lost upstream improvements for skills that never conflict.
- **Depend on upstream unchanged**: `to-issues` would keep writing "issue / story" into
  downstream repos, contradicting each repo's own `CONTEXT.md`.

Consequence: the "single source" of ADR-0003 is scoped to this repo's **authored-or-forked
delta**, not to everything in `~/.claude/`. Upstream skills coexist in user scope; this repo
governs only what it authors or forks.
