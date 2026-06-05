# Global harness machinery, not an install-per-project template

The original design made this repository a **template**: it carried the AI Layer
(`CLAUDE.md`, `.claude/commands/`, `.claude/skills/`, `examples/`) and an `install.sh` that
**copied** those files into each new project. Reuse meant N copies, one per downstream repo.

We are dropping that model. This repository is now the **single source of the
project-agnostic harness machinery** — the generic `CLAUDE.md` rules, `.claude/commands/`,
`.claude/skills/`, and `examples/` that do not change from project to project. That machinery
is version-controlled here and **synced to user scope (`~/.claude/`)**, so it applies to
every repo at once. `install.sh` retires: there are no more per-project copies to drift or to
upgrade one-by-one. Editing the machinery here, then syncing, upgrades every repo together.

This splits the AI Layer along the line drawn while resolving this decision:

- **Project-agnostic machinery** (rules, commands, skills, examples) → lives here → global
  `~/.claude/`. Owned and versioned by *this* repo.
- **Project-specific context** (each repo's own `CONTEXT.md`, `docs/adr/`, the `CLAUDE.md`
  "Project specifics" section, `.agents/plans` + `.agents/reports`) → stays in the downstream
  repo, **version-controlled with that repo's code**.

The second half preserves Cole Medin's core principle — the AI Layer evolves *with* the code
it governs, and each repo's System Evolution improves *that repo's* layer. We keep that for
project-specific context; we deliberately do **not** apply it to the generic machinery, which
has no reason to diverge per project and benefits from a single upgrade point.

Alternatives rejected:
- **Template + `install.sh` per project** (the prior design): machinery diverges per repo,
  copies drift, and there is no single place to upgrade everyone.
- **Centralize everything, including project context**: breaks "versioned with the code" and
  per-project System Evolution; a repo's glossary and decisions must live with its code.

Consequence: the "control plane" idea — one cockpit driving work across many downstream repos
— is **out of scope for this repo**. That is a separate, later **orchestrator** project
(Archon-like: a `git worktree` DAG over multiple repos), not the machinery source. This repo
is the machinery source, not the orchestrator. The two are different layers and must not be
conflated.

This decision invalidates the "template / ships into every new project" framing in
`README.md` and the preamble of `CONTEXT.md`; both need rewriting to describe the
global-machinery model instead.
