# Skill-tool dependency closure is part of harness freshness; user-invoked skills are leaves

**Status:** Extends ADR-0007 (per-item symlinks) and ADR-0029 (freshness gate). Amends
ADR-0029's "deliberately excludes" list: `domain-modeling` is linked, as a hard dependency.

## Context

Upstream (Matt Pocock v1.2) restructured its skills around **shared skills reached through the
Skill tool**: `grill-me` is one line, `Call the Skill tool with "grilling"`; `grill-with-docs`
calls `grilling` and `domain-modeling`; `triage`, `improve-codebase-architecture` and `tdd`
call `grilling` / `domain-modeling` / `codebase-design`. The per-item symlinks of ADR-0007
carried only the names the operator picked in June; none of the three shared skills were linked.
Every wrapper was broken at the Skill tool from upstream 2026-05-31 until 2026-09-13 and nothing
said so — ADR-0029's check (c) sees a dangling link, not a link whose target calls a name that
is not there.

The same day, a probe showed the second half of the rule: `strategic-planning` told the model to
"run `to-spec`" / "run `to-tickets`" / "emit a handoff via `handoff`" / "run
`grill-with-docs`". All four are `disable-model-invocation: true`. The harness refuses them at
the Skill tool — *"cannot be used with Skill tool… Ask the user to run /to-spec themselves. Do
not replicate this skill's workflow by other means"* — so the PRD and Issue steps of Phase 1
could never fire as written. Upstream records the same invariant (`.agents/invocation.md`): a
user-invoked skill is reachable **only by the human typing its name**; no skill can call one.

## Decision

1. **Dependency closure is a freshness check.** `harness_freshness.sh` gains check (f): over
   every `~/.claude/{skills/*/SKILL.md,commands/*.md}`, each `Call the Skill tool with "X"` must
   resolve to `~/.claude/skills/X/SKILL.md` (**missing** finding otherwise) and X must be
   model-invoked (**unreachable** finding if `disable-model-invocation: true`). It scans the whole
   file class — linked and real, skills and commands — never a name subset.
2. **User-invoked skills are leaves.** A skill or command never invokes one; it tells the human
   to run `/name`. `strategic-planning` is rephrased that way for `to-spec`, `to-tickets`,
   `handoff`, `grill-with-docs`. Same session, so the Naming boundary (ADR-0028) stays in context.
3. **Shared dependencies are linked, not forked.** `grilling`, `domain-modeling`,
   `codebase-design` are linked from the upstream checkout. ADR-0004's fork trigger (output
   pollutes the glossary) does not fire: they are vocabulary and interview mechanics.

## Consequences

- `domain-modeling` is model-invoked with a broad trigger ("writing or editing a CONTEXT.md, or
  recording or editing an ADR"). Linking it means the model may reach for it on canonical-doc
  edits in any project — the reason ADR-0029 listed it as an intruder. Accepted for now because
  `grill-with-docs`, the only sanctioned Alignment entry (CLAUDE.md), hard-depends on it. The
  CLAUDE.md rule that Alignment enters only via `strategic-planning` escalation still governs;
  an auto-fire outside that path is a miss to record. **Revisit** if it fires unwanted: fork
  `grill-with-docs` to a project-owned skill without the `domain-modeling` call (ADR-0004
  would then be triggered by *process* pollution, a new trigger to write down).
- The check resolves against user scope only. A project-scope `.claude/skills/X` or a
  plugin-namespaced `a:b` target is skipped, not reported.
- Every pull of the upstream checkout can add a new shared dependency; check (f) names it at the
  next session start instead of the next failed grill.

## Rejected

- **Run upstream's `scripts/link-skills.sh`** — links all 33 non-`misc/` skills into
  `~/.claude/skills` and `~/.agents/skills`, adds our two aliases' targets under their upstream
  names (`code-review`, `diagnosing-bugs` beside `review`, `diagnose` — the same skill twice),
  prunes nothing, and upstream labels it dev-only and unsupported. Closure by "link everything"
  also re-admits `implement` (PR #105).
- **Leave `grill-with-docs` broken** — it is the Alignment entry point; a silent failure there
  is the class of defect ADR-0029 exists to surface.
- **Have the model read the user-invoked SKILL.md by path** — the harness's refusal text forbids
  replicating the workflow by other means; upstream's invariant says the same.
