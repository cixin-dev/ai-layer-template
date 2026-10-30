# The glossary file follows upstream's rename: CONTEXT.md → GLOSSARY.md

**Status:** Applies ADR-0004 (fork only on glossary pollution) the way ADR-0028 did — an
upstream rename is synced, not forked. Leaves ADR-0002's nouns-vs-process boundary intact;
only the file's name moves.

Matt Pocock's skills renamed the domain-doc convention `CONTEXT.md` / `CONTEXT-MAP.md` →
`GLOSSARY.md` / `GLOSSARY-MAP.md` in every skill that reads or writes it (upstream #1120;
among the skills linked here: `domain-modeling`, `codebase-design`,
`improve-codebase-architecture`, `diagnosing-bugs`, `tdd`, `triage`), with no fallback —
"the skills only look for `GLOSSARY.md`/`GLOSSARY-MAP.md` going forward." This repo's
glossary declared "the filename is always `CONTEXT.md`", so once the mattpocock checkout
was pulled, one session received contradictory instructions from the two layers. The
likely outcome — `domain-modeling` creating a fresh `GLOSSARY.md` beside the existing
`CONTEXT.md` — is the second drifting source of truth that ADR-0002 and ADR-0022 exist to
prevent.

**Decision:** rename the file to `GLOSSARY.md`, here and in every downstream repo, and
update every live reference: `CLAUDE.md`, `README.md`, `strategic-planning`, `/validate`,
the `security_guard.py` docstring, `piv_check` and its fixtures, and the draft
`piv-ralph-loop` PRD. The concept is untouched: **Ubiquitous Language** still names the
concept, and "glossary" still names only the file.

Append-only records keep the old name. ADRs 0001–0030 and the archived plans, reports and
tickets under `.agents/` say `CONTEXT.md`; read it as `GLOSSARY.md`. ADR-0002's title is
not rewritten.

Alternatives rejected:
- **Keep `CONTEXT.md` and pin the mattpocock checkout before #1120** — `harness_freshness.sh`
  (ADR-0029) would name the checkout as behind in every session, and "act on its lines,
  never dismiss them" cannot hold for a deliberate pin. Every later upstream fix is lost too.
- **Fork the affected skills back to `CONTEXT.md` (the ADR-0004 remedy)** — ADR-0004's
  trigger is a skill's output *vocabulary* polluting the glossary; a filename is not
  vocabulary. A fork would carry divergence across many skills for no conceptual payoff.

Consequence: each downstream repo needs a one-time `git mv CONTEXT.md GLOSSARY.md` (and
`CONTEXT-MAP.md` → `GLOSSARY-MAP.md` if present) plus its own references; until then the
upstream skills do not see its glossary. Upstream's `setup-matt-pocock-skills` offers the
same `git mv` (#1228).
