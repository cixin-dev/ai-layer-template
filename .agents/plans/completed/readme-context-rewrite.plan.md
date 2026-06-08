# Plan: README + CONTEXT.md Preamble Rewrite

## Summary

Rewrite `README.md` and the `CONTEXT.md` preamble so they describe the global-machinery
model (ADR-0003) instead of the retired "template / install into every project" model.
`README.md` gets a new title, intro, ownership-split section, updated Layout block, and a
`sync.sh` usage section replacing `Install`. `CONTEXT.md` gets only its 5-line preamble
paragraph replaced; the `## Language` section is left byte-for-byte unchanged.

## User Story

As a developer onboarding to this repo, I want the README and CONTEXT.md preamble to
describe what the repo actually is today — the single, synced source of global harness
machinery — so that I understand the ownership split and know to run `sync.sh`, not `install.sh`.

## Metadata

| Field | Value |
|-------|-------|
| Type | REFACTOR |
| Complexity | LOW |
| Systems affected | `README.md`, `CONTEXT.md` |
| Issue | 04 |

## Current State (what is wrong)

### README.md

- Title and intro frame this as a "drop-in AI Layer for any codebase" (`README.md:1–6`)
- Layout block (`README.md:31–49`) lists `scripts/install.sh` (deleted); missing `scripts/sync.sh` and the `strategic-planning` skill
- Install section (`README.md:51–68`) documents the retired `install.sh` copy commands
- "After installing" section (`README.md:70–81`) references the old template workflow

### CONTEXT.md

- Lines 5–9 say "This repository is a **template**: it ships this `CONTEXT.md` pre-seeded … so that every new project created from it starts with the same language." — contradicts ADR-0003

## Patterns to Follow

This is a pure documentation task — no code patterns apply. All edits are `Edit` tool calls
on the two target files. The Language section of `CONTEXT.md` must not be touched.

```
// SOURCE: docs/adr/0003-global-harness-machinery-not-install-per-project-template.md:14–20
The key ownership split to communicate:
  - Project-agnostic machinery (rules, commands, skills, examples) → lives here → global ~/.claude/
  - Project-specific context (each repo's own CONTEXT.md, docs/adr/, the CLAUDE.md
    "Project specifics" section, .agents/plans + .agents/reports) → stays in each
    downstream repo, version-controlled with that repo's code.
```

```
// SOURCE: scripts/sync.sh:6–9
sync.sh interface:
  sync.sh [--dry-run]
  --dry-run   Print what would happen; change nothing.
  -h|--help   Show this help.
```

```
// SOURCE: .agents/reports/sync-sh-retire-install-report.md:46
Upstream skills (not vendored here, never appear in sync.sh output):
  grill-with-docs, to-prd, grill-me, to-issues
```

## Files to Change

| File | Action | Purpose |
|------|--------|---------|
| `README.md` | UPDATE | Replace template framing with global-machinery model |
| `CONTEXT.md` | UPDATE | Replace preamble paragraph (lines 5–9 only); leave `## Language` section untouched |

## Tasks

### Task 1: Replace README.md title and intro paragraph

- **File**: `README.md`
- **Action**: UPDATE lines 1–6
- **Old content** (exact):
  ```
  # AI Layer Template
  
  A language-agnostic, drop-in **AI Layer** for any codebase: the versioned set of rules,
  commands, skills, and examples that tells Claude Code how to think, work, and verify in a
  project. It encodes a small set of battle-tested ideas from agentic-engineering practice so
  you don't have to re-derive them per project.
  ```
- **New content**:
  ```
  # AI Layer Machinery
  
  The **single source of project-agnostic harness machinery** — rules, commands, skills, and
  examples that tell Claude Code how to think, work, and verify. Version-controlled here,
  synced to user scope (`~/.claude/`), so every repo gets the same machinery without per-repo
  copies that drift.
  ```
- **Validate**: `grep "AI Layer Template" README.md` → no output; `grep "drop-in" README.md` → no output

### Task 2: Add ownership-split section after the intro (before "What's an AI Layer?")

- **File**: `README.md`
- **Action**: INSERT a new section between the intro paragraph and `## What's an AI Layer?`
- **Insert after** the intro paragraph (after the new text from Task 1), before the line `## What's an AI Layer?`
- **New section**:
  ```
  ## Ownership split
  
  | What | Where it lives | Owned by |
  |------|----------------|----------|
  | Project-agnostic machinery (rules, commands, skills, examples) | This repo → `~/.claude/` | This repo |
  | Project-specific context (`CONTEXT.md`, `docs/adr/`, `CLAUDE.md` "Project specifics", `.agents/`) | Each downstream repo, versioned with its code | That repo |
  
  Editing the machinery here and re-running `sync.sh` upgrades every downstream repo at once.
  ```
- **Validate**: `grep "Ownership split" README.md` → found; `grep "downstream repo" README.md` → found

### Task 3: Update Layout block

- **File**: `README.md`
- **Action**: UPDATE the entire `## Layout` section (lines 29–49 in original)
- **Old content** (exact):
  ````
  ## Layout
  
  ```
  ai-layer-template/
  ├── CLAUDE.md                       # always-loaded rules: Smart Zone, PIV Loop,
  │                                   #   System Evolution, Conventions
  ├── .claude/
  │   ├── commands/
  │   │   ├── plan.md                 # PIV: Plan phase
  │   │   ├── implement.md            # PIV: Implement phase + E2E gate
  │   │   └── retroactive.md          # System Evolution: improve the AI Layer
  │   └── skills/
  │       ├── piv-loop/SKILL.md
  │       ├── system-evolution/SKILL.md
  │       └── tdd-gate/SKILL.md
  ├── examples/
  │   └── deep-module-pattern.md      # on-demand context: a pattern to mirror
  ├── scripts/
  │   └── install.sh                  # copy the AI Layer into a project
  └── README.md
  ```
  ````
- **New content**:
  ````
  ## Layout
  
  ```
  ai-layer-template/
  ├── CLAUDE.md                       # always-loaded rules: Smart Zone, PIV Loop,
  │                                   #   System Evolution, Conventions
  ├── .claude/
  │   ├── commands/
  │   │   ├── plan.md                 # PIV: Plan phase
  │   │   ├── implement.md            # PIV: Implement phase + E2E gate
  │   │   └── retroactive.md          # System Evolution: improve the AI Layer
  │   └── skills/
  │       ├── piv-loop/SKILL.md
  │       ├── strategic-planning/SKILL.md
  │       ├── system-evolution/SKILL.md
  │       └── tdd-gate/SKILL.md
  ├── examples/
  │   └── deep-module-pattern.md      # on-demand context: a pattern to mirror
  ├── scripts/
  │   └── sync.sh                     # symlink machinery into ~/.claude/
  └── README.md
  ```
  ````
- **Validate**: `grep "install.sh" README.md` → no output; `grep "sync.sh" README.md` → ≥1 result; `grep "strategic-planning" README.md` → ≥1 result

### Task 4: Replace Install section with Sync section

- **File**: `README.md`
- **Action**: UPDATE the entire `## Install` section (lines 51–68 in original)
- **Old content** (exact):
  ````
  ## Install
  
  From a checkout of this template:
  
  ```bash
  # Preview (changes nothing):
  bash scripts/install.sh --dry-run /path/to/your/project
  
  # Install (preserves any existing files):
  bash scripts/install.sh /path/to/your/project
  
  # Overwrite existing AI Layer files:
  bash scripts/install.sh --force /path/to/your/project
  ```
  
  The installer copies **only** the AI Layer — `CLAUDE.md`, `.claude/`, and `examples/`. It
  never copies this README or the script itself, and it won't overwrite files in your project
  unless you pass `--force`.
  ````
- **New content**:
  ````
  ## Sync
  
  From a checkout of this repo:
  
  ```bash
  # Preview (changes nothing):
  bash scripts/sync.sh --dry-run
  
  # Apply:
  bash scripts/sync.sh
  ```
  
  `sync.sh` symlinks each owned skill and command into `~/.claude/{skills,commands}/`. Run it
  once after cloning; re-run after pulling updates to pick up new or renamed items. Real files
  at a target path are warned and skipped — they are never overwritten.
  
  > **Note:** `grill-with-docs`, `to-prd`, and `to-issues` are referenced in the workflow but
  > are not vendored in this repo — they live upstream and are not synced here.
  ````
- **Validate**: `grep "install.sh" README.md` → no output; `grep "sync.sh" README.md` → ≥2 results; `grep "dry-run" README.md` → ≥1 result

### Task 5: Update "After installing" → "After syncing"

- **File**: `README.md`
- **Action**: UPDATE the `## After installing` section (lines 70–81 in original)
- **Old content** (exact):
  ```
  ## After installing
  
  1. Open `CLAUDE.md` and fill in the **Project specifics** section (stack, the project's
     verify commands, architecture, known footguns). Keep it lean.
  2. Add project-specific patterns to `examples/` as conventions emerge.
  3. Use the loop: `/plan` in a fresh session → `/implement <plan>` in another fresh session
     → review → `/retroactive` whenever something slips through.
  
  This template is intentionally stack-neutral — there's no `package.json`, `tsconfig`,
  `pyproject.toml`, or other tooling. Each project supplies its own commands; the AI Layer
  stays portable.
  ```
- **New content**:
  ```
  ## After syncing
  
  In each downstream repo:
  
  1. Add a `CONTEXT.md` (glossary), `docs/adr/` (architecture decisions), and fill in the
     **Project specifics** section of `CLAUDE.md` (stack, verify commands, architecture,
     known footguns). Keep it lean. Version-control all of this with the repo's code.
  2. Add project-specific patterns to that repo's `examples/` as conventions emerge.
  3. Use the loop: `/plan` in a fresh session → `/implement <plan>` in another fresh session
     → review → `/retroactive` whenever something slips through.
  
  The machinery itself is stack-neutral — no `package.json`, `tsconfig`, or `pyproject.toml`.
  Each project supplies its own verify commands; the AI Layer stays portable.
  ```
- **Validate**: `grep "After installing" README.md` → no output; `grep "After syncing" README.md` → found; `grep "downstream repo" README.md` → ≥1 result

### Task 6: Rewrite CONTEXT.md preamble paragraph

- **File**: `CONTEXT.md`
- **Action**: UPDATE lines 5–9 only (the single paragraph starting "This repository is a **template**:")
- **Constraint**: Lines 11 onward (`## Language` and everything below) must not be touched — not even whitespace.
- **Old content** (exact):
  ```
  This repository is a **template**: it ships this `CONTEXT.md` pre-seeded with the Harness
  vocabulary (below) so that every new project created from it starts with the same language.
  As a project grows, its own domain terms (e.g. `Session`, `Turn`, `Model Request` — the
  words specific to what that software actually does) are added to this same file. The
  filename is always `CONTEXT.md`.
  ```
- **New content**:
  ```
  This repository is the **single source of project-agnostic harness machinery** — synced
  globally to `~/.claude/`, not copied into each project. Each downstream repo keeps its own
  `CONTEXT.md` versioned with its code; that file is where the repo's domain terms (e.g.
  `Session`, `Turn`, `Model Request`) accumulate as the project grows. This copy captures the
  machinery's own Ubiquitous Language — the terms that name the harness concepts themselves.
  The filename is always `CONTEXT.md`.
  ```
- **Validate**:
  - `grep "every new project created from it" CONTEXT.md` → no output
  - `grep "single source" CONTEXT.md` → found
  - `diff <(sed -n '11,$p' CONTEXT.md) <(sed -n '11,$p' CONTEXT.md.bak)` — Language section unchanged (verify by reading; do not create a `.bak` file — just confirm `## Language` is at the first header after the preamble and the content below it is untouched)

## Validation

No build system. Acceptance checks are shell greps + visual inspection:

```bash
# README.md — old framing absent:
grep "install.sh" README.md         # → no output
grep "drop-in" README.md            # → no output
grep "After installing" README.md   # → no output
grep "AI Layer Template" README.md  # → no output

# README.md — new framing present:
grep "sync.sh" README.md            # → ≥ 2 lines
grep "strategic-planning" README.md # → ≥ 1 line
grep "Ownership split" README.md    # → 1 line
grep "After syncing" README.md      # → 1 line
grep "dry-run" README.md            # → ≥ 1 line
grep "grill-with-docs" README.md    # → 1 line (the upstream note)

# CONTEXT.md — old framing absent:
grep "every new project created from it" CONTEXT.md  # → no output
grep "ships this" CONTEXT.md                          # → no output

# CONTEXT.md — new framing present:
grep "single source" CONTEXT.md     # → 1 line

# CONTEXT.md — Language section intact (spot-check):
grep "^## Language" CONTEXT.md      # → 1 line, at line ~11
grep "^\\*\\*Harness\\*\\*:" CONTEXT.md   # → found (first glossary entry)
```

## Acceptance Criteria

- [ ] `README.md` no longer presents the repo as a copy-in template; no `install.sh` reference anywhere in the file
- [ ] `README.md` Layout block shows `scripts/sync.sh` and `strategic-planning/SKILL.md`; `install.sh` absent
- [ ] `README.md` has a `## Sync` section documenting `sync.sh --dry-run` and `sync.sh`
- [ ] `README.md` has an ownership-split section distinguishing project-agnostic machinery from project-specific context
- [ ] `README.md` notes that `grill-with-docs`, `to-prd`, and `to-issues` are upstream, not vendored here
- [ ] `CONTEXT.md` preamble paragraph describes the global-machinery model, not "ships into every new project"
- [ ] `CONTEXT.md` `## Language` section and everything below is byte-for-byte unchanged
- [ ] All validation greps above pass
