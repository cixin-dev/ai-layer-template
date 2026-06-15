# PRD — Phase 1 Machinery (Strategic Planning + global sync)

Status: ready-for-agent
Source decisions: ADR-0003, ADR-0004, ADR-0005, ADR-0006, ADR-0007 (and ADR-0001, ADR-0002 for context)

## Problem Statement

This repository ships **Phase 2** machinery (the PIV Loop: `plan` / `implement` /
`retroactive` commands, plus `piv-loop`, `system-evolution`, `tdd-gate` skills) but nothing
for **Phase 1 — Project Setup**. A solo developer with a non-technical supervisor (ADR-0001)
has no way to turn a brain-dump conversation into a reviewable PRD and an ordered set of
Tickets that Phase 2 can consume. The judgment of a human PM — leading with the problem,
asking "why", naming Non-Goals, holding scope — is simply absent.

Two further problems sit underneath that gap:

1. **Distribution.** The repo still describes itself as a *template* with an `install.sh` that
   **copies** the AI Layer into each downstream project. That model produces N drifting
   copies with no single upgrade point (ADR-0003).
2. **Vocabulary pollution.** The obvious off-the-shelf decomposition skill, upstream
   `to-issues`, writes "issue / story / Jira" — vocabulary this project's `CONTEXT.md`
   explicitly forbids (`_Avoid_: issue, story`). Wiring it in unchanged would push
   glossary-violating artifacts into every downstream repo (ADR-0004).

## Solution

Build the Phase 1 machinery as **skills** (Phase 1 is interactive dialogue, so it is skills,
not commands — ADR-0005), and change distribution from copy-per-project to a single
globally-synced source.

From the developer's perspective, after this ships:

- They invoke a single **`strategic-planning`** persona skill in the main session. It runs a
  lean PM persona that drives **brain dump → clarifying questions → PRD → Tickets**, standing
  in for the absent human PM. During the brain dump it watches for newly surfaced vocabulary
  and captures it into `CONTEXT.md` inline; a term escalates — via a handoff to a fresh session —
  to a full `grill-with-docs` Alignment pass only when it *conflicts* with an existing entry or is
  *coupled* to other new terms (conflict-or-coupling, not a count). A lone additive term stays inline.
- The PRD it produces lands at `.agents/prds/{name}.prd.md`; the Tickets land as one file each
  at `.agents/tickets/{NN}-{slug}.md`, with ordering/dependencies in per-file frontmatter
  (`blocked_by: [...]`). No "issue", no external tracker.
- They run a single **`sync.sh`** once to mount this repo's machinery into user scope
  (`~/.claude/`) via per-item symlinks. Editing the machinery here upgrades every repo at
  once — no per-project copies, no `install.sh`.

## User Stories

1. As a solo developer, I want a `strategic-planning` skill that adopts a PM persona in my
   main session, so that I get a human-PM's judgment without hiring one.
2. As a developer, I want the skill to lead with the problem and ask "why" repeatedly, so that
   I don't lock in a solution before the problem is understood.
3. As a developer, I want the persona to push me to name **Non-Goals** and hold scope, so that
   the PRD has a real boundary instead of sprawling.
4. As a developer, I want the persona to be willing to say "no" to scope creep, so that the
   feature stays shippable.
5. As a developer, I want the skill to orchestrate brain dump → clarifying questions → `to-prd`
   → `to-tickets` in one main-session flow, so that I don't manually chain steps.
6. As a developer, I want the persona to run in the **main session** (not a sub-agent), so that
   it can hold the multi-turn interactive dialogue a summary-returning sub-agent cannot
   (ADR-0006).
7. As a developer, I want newly surfaced domain terms captured into `CONTEXT.md` inline during
   the brain dump, so that the glossary stays current without a separate ceremony.
8. As a developer, I want a term to escalate to a full `grill-with-docs` Alignment pass via a
   fresh-session handoff only when it *conflicts* with an existing entry or is *coupled* to other
   new terms (conflict-or-coupling, not a count), so that minor new vocabulary
   doesn't derail planning.
9. As a developer, I want the PRD written to `.agents/prds/{name}.prd.md`, so that intent is
   version-controlled with the code it governs.
10. As a developer, I want a `to-tickets` skill that decomposes a PRD into tracer-bullet
    vertical slices, so that each Ticket is independently grabbable by Phase 2.
11. As a developer, I want each Ticket written as **one file** at
    `.agents/tickets/{NN}-{slug}.md`, so that `/plan` consumes exactly one disk unit.
12. As a developer, I want Ticket ordering and dependencies expressed as `blocked_by: [...]`
    frontmatter in each file, so that there is no separate index to maintain.
13. As a developer, I want `to-tickets` to use **Ticket** vocabulary throughout — never
    "issue", "story", or "Jira" — so that artifacts never violate `CONTEXT.md` (ADR-0004).
14. As a developer, I want `to-tickets` to keep the upstream tracer-bullet / HITL-vs-AFK /
    dependency-ordering logic, so that I lose none of `to-issues`' value in the fork.
15. As a developer, I want `to-tickets` to present the proposed slice breakdown for my approval
    before writing files, so that I can correct granularity and dependencies first.
16. As a developer, I want a `sync.sh` that symlinks each skill/command this repo owns into
    `~/.claude/{skills,commands}/`, so that the machinery applies to every repo at once.
17. As a developer, I want `sync.sh` to symlink **per item**, not the whole directory, so that
    coexisting upstream (Matt Pocock) skills in `~/.claude/` are never clobbered (ADR-0007).
18. As a developer, I want `sync.sh` to remove the specific superseded upstream symlinks (e.g.
    `to-issues` when it links `to-tickets`) in the same run, so that no two-producer state ever
    persists (ADR-0004, ADR-0007).
19. As a developer, I want `sync.sh` to use **symlinks, not copies**, so that editing the
    machinery here upgrades every repo instantly with no drift (ADR-0003).
20. As a developer, I want `sync.sh` to be idempotent, so that re-running it is safe and
    converges to the same state.
21. As a developer, I want a `sync.sh --dry-run` that prints exactly which links it would
    create and which upstream symlinks it would remove, so that I can preview before mutating
    `~/.claude/`.
22. As a developer, I want `install.sh` retired, so that there is no surviving copy-per-project
    path to drift (ADR-0003).
23. As a developer, I want `README.md` rewritten away from the "template / install into every
    project" framing to the global-machinery + per-project-context split, so that the docs
    match reality (ADR-0003).
24. As a developer, I want the `CONTEXT.md` preamble rewritten away from "ships this into every
    new project," so that the glossary's own framing matches the global-machinery model.
25. As a developer, I want upstream `grill-with-docs` and `to-prd` **referenced, not vendored**,
    since their output is already glossary-consistent, so that the fork surface stays minimal
    (ADR-0004, ADR-0005).
26. As a developer, I want the `strategic-planning` skill to call the upstream `to-prd` for the
    mechanical PRD generation while supplying the judgment layer itself, so that the persona is
    not redundant with `to-prd` (ADR-0006).
27. As a developer, I want all new Phase 1 machinery authored as **skills** (not commands),
    while Phase 2 stays commands, so that packaging follows interaction shape (ADR-0005).
28. As a developer reviewing the change, I want every new artifact's vocabulary checked against
    `CONTEXT.md`, so that nothing I ship contradicts the glossary.

## Implementation Decisions

**Modules built/modified**

- **`strategic-planning` skill** (new, `.claude/skills/strategic-planning/SKILL.md`). A
  main-session persona skill with `disable-model-invocation: true` (interactive session, must
  not auto-trigger — ADR-0005). Mines only the *judgment instincts* from the agency PM persona
  (problem-first, repeated "why", Non-Goals, say-no, scope discipline); drops all enterprise
  GTM/sprint/roadmap/RICE/NPS machinery (ADR-0006). Orchestrates: brain dump → clarifying
  questions → invoke `to-prd` → invoke `to-tickets`. Carries the **Alignment checkpoint**:
  capture lone/additive terms into `CONTEXT.md` inline; escalate to a fresh-session
  `grill-with-docs` handoff only on *conflict-or-coupling* (a term contradicting an existing entry,
  or ≥2 interdependent new terms). Does **not** create any `.claude/agents/` file.
- **`to-tickets` skill** (new, forked from upstream `to-issues`,
  `.claude/skills/to-tickets/SKILL.md`). Same tracer-bullet vertical-slice logic, HITL/AFK
  typing, and dependency-ordered publishing. Differences: vocabulary becomes **Ticket**
  throughout (no issue/story/Jira); output is **one file per Ticket** at
  `.agents/tickets/{NN}-{slug}.md` rather than a tracker API call; dependencies are
  `blocked_by: [...]` frontmatter rather than tracker links. Forked (not referenced) precisely
  because its output would otherwise pollute the glossary (ADR-0004).
- **`sync.sh`** (new, `scripts/sync.sh`). Per-item symlink installer into user scope. (1) For
  each skill/command this repo owns, create/refresh a symlink in `~/.claude/{skills,commands}/`
  pointing back into this repo's working tree. (2) Remove the specific superseded upstream
  symlinks this repo's forks replace (link `to-tickets` ⇒ remove `~/.claude/skills/to-issues`).
  Symlink not copy; per-item not whole-directory; idempotent. Supports `--dry-run` that prints
  the planned create/remove actions and mutates nothing.
- **`scripts/install.sh`** — **deleted**. Its direction inverts: push-into-project becomes
  link-into-global (ADR-0007).
- **`README.md`** — rewritten: global-machinery model, the project-agnostic-machinery vs
  project-specific-context split, `sync.sh` usage replacing the install section, layout block
  updated (drop `install.sh`, add `sync.sh`, `strategic-planning`, `to-tickets`).
- **`CONTEXT.md`** preamble (lines ~5–10) — rewritten away from "ships this `CONTEXT.md` into
  every new project" to the global-machinery framing. Glossary **Language** section unchanged.

**Ownership / sync boundary (ADR-0003)**

- Project-agnostic machinery (rules, commands, skills, examples) → owned here → symlinked to
  global `~/.claude/`.
- Project-specific context (`CONTEXT.md`, `docs/adr/`, `CLAUDE.md` "Project specifics",
  `.agents/plans`, `.agents/reports`, `.agents/prds`, `.agents/tickets`) → stays in each repo,
  versioned with its code.

**Out-of-band**

- The "control plane" / multi-repo orchestrator is explicitly **out of scope** for this repo
  (ADR-0003) — a separate later project.

**What sync.sh owns to link** (derived, confirm at implementation time): commands `plan`,
`implement`, `retroactive`; skills `piv-loop`, `system-evolution`, `tdd-gate`,
`strategic-planning`, `to-tickets`. Superseded upstream to remove: `to-issues`. Left upstream
and merely referenced: `grill-with-docs`, `to-prd`, `grill-me`.

## Testing Decisions

A good test here asserts **external behavior at the highest available seam**, never internal
structure. Most of this feature is prose skills, which are validated structurally, not
behaviorally. The one mechanically-testable artifact is `sync.sh`.

- **`sync.sh` — dry-run output assertion (chosen seam).** Tests drive `sync.sh --dry-run` and
  assert on its printed plan: that it would link each owned skill/command into the expected
  `~/.claude/` path, that it would remove the superseded `to-issues` symlink, and that it
  reports no destructive action against coexisting upstream symlinks. `--dry-run` mutates
  nothing, so tests need no real `~/.claude` and leave no residue. Cover: (a) fresh state — all
  owned items planned for linking; (b) supersession — `to-issues` planned for removal when
  `to-tickets` is linked; (c) idempotency — a dry-run reported against an already-synced state
  plans no changes; (d) upstream safety — `grill-with-docs` / `to-prd` / `grill-me` never
  appear in the removal plan. Prior art: the retired `install.sh` already modeled `--dry-run`
  as "print what would happen; change nothing" — mirror that contract and its `[sync] would …`
  line style.
- **Skills (`strategic-planning`, `to-tickets`) — structural validation, not behavioral.**
  Assert valid frontmatter (`name`, `description`; `disable-model-invocation: true` on
  `strategic-planning`), that internal references resolve, and — the glossary gate — that
  `to-tickets` contains **no** forbidden vocabulary (`issue`, `story`, `Jira`) and writes to
  the `.agents/tickets/{NN}-{slug}.md` path with `blocked_by` frontmatter.
- **Docs (`README.md`, `CONTEXT.md`).** Assert the template/`install.sh` framing is gone and
  the global-machinery framing is present; glossary **Language** entries unchanged.

## Out of Scope

- The multi-repo **control plane / orchestrator** (Archon-like worktree DAG) — separate later
  project (ADR-0003).
- Any rewrite of the existing **Phase 2 commands** (`plan` / `implement` / `retroactive`) —
  they stay commands, unchanged (ADR-0005).
- Vendoring `grill-with-docs` or `to-prd` — referenced upstream, not forked (ADR-0004).
- A behavioral/E2E test that actually mutates `~/.claude` — the dry-run seam was chosen over a
  temp-HOME integration test; real mutation is verified manually on first run.
- Creating a `.claude/agents/` PM sub-agent — explicitly rejected (ADR-0006).
- Standing up an external issue tracker / GitHub Issues — this repo has no remote; Tickets are
  files.

## Further Notes

- **Cadence reminder** (`CONTEXT.md` Phase 1 entry): Alignment is *reentrant* (run at birth,
  re-entered whenever new terms surface); Strategic Planning runs *once per feature* and is the
  step that notices new language and reopens Alignment. The `strategic-planning` skill must
  embody this — its brain-dump Alignment checkpoint is the reentry trigger.
- **Fragility accepted** (ADR-0007): `~/.claude/` symlinks point into this repo's NFS working
  tree; if the repo moves or the mount drops, links break — the same fragility upstream
  symlinks already carry, accepted deliberately.
- Suggested Ticket slicing for Phase 2 (to confirm in `to-tickets`): (1) `sync.sh` + delete
  `install.sh` + dry-run tests; (2) `to-tickets` fork; (3) `strategic-planning` skill;
  (4) README + CONTEXT preamble rewrite. Slices 1–2 are AFK; 3 likely HITL (persona judgment
  review); 4 AFK.
