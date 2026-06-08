# AI Layer Machinery

The **single source of project-agnostic harness machinery** — rules, commands, skills, and
examples that tell Claude Code how to think, work, and verify. Version-controlled here,
synced to user scope (`~/.claude/`), so every repo gets the same machinery without per-repo
copies that drift.

## Ownership split

| What | Where it lives | Owned by |
|------|----------------|----------|
| Project-agnostic machinery (commands + skills) | This repo; commands + skills symlinked to `~/.claude/` via `sync.sh` | This repo |
| Project-specific context (`CONTEXT.md`, `docs/adr/`, `CLAUDE.md` "Project specifics", `.agents/`) | Each downstream repo, versioned with its code | That repo |

`CLAUDE.md` and `examples/` are not synced — copy them into each downstream repo manually. Because `sync.sh` creates symlinks (not copies), edits to already-linked skills and commands are visible in `~/.claude/` instantly; re-run `sync.sh` only to pick up new or renamed items.

> **Note:** This repo self-applies this pattern — its own `CONTEXT.md`, `docs/adr/`, and `.agents/` are the machinery's project-specific context, versioned alongside the machinery itself.

## What's an AI Layer?

`CLAUDE.md` + `.claude/commands/` + `.claude/skills/` + `examples/`. It's a code asset:
versioned, reviewable in PRs, shareable across a team. Improving it once protects everyone
who uses it afterward.

## The core ideas

- **Smart Zone** — an agent does its best work in roughly the first ~100k tokens; design
  the workflow to stay there. One job per session, `/clear` over compaction, files as the
  only durable memory.
- **PIV Loop** — Plan → Implement → Validate, each in a fresh session, with a written plan
  as the only handoff between phases.
- **System Evolution** — when a bug slips through, fix the AI Layer (not just the code) so
  the class of problem can't recur. Each fix compounds.
- **Verification-led / TDD gate** — define how you'll verify before you build; small
  vertical tracer-bullet slices over big horizontal passes.

These live in [`CLAUDE.md`](CLAUDE.md) and the skills under
[`.claude/skills/`](.claude/skills/).

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
at a target path are warned and skipped — they are never overwritten. If `sync.sh` warns
about a path, remove that file or directory manually and re-run to replace it with a symlink.

> **Migrating from `install.sh`?** The old installer left real file copies in `~/.claude/`.
> Run `bash scripts/sync.sh --dry-run` to see what will be skipped, remove those paths, then
> run `bash scripts/sync.sh`.

> **Note:** `grill-with-docs`, `to-prd`, and `to-issues` are referenced in the workflow but
> are not vendored here — they are external Claude Code skills (e.g. from the FleetView skill
> registry) that you install separately into `~/.claude/skills/`.

## After syncing

In each downstream repo:

1. Copy `CLAUDE.md` and `examples/` from this repo into the downstream repo (they are not
   synced by `sync.sh`). Fill in the **Project specifics** section of `CLAUDE.md` (stack,
   verify commands, architecture, known footguns). Add a `CONTEXT.md` (glossary) and
   `docs/adr/` (architecture decisions). Keep it lean. Version-control all of this with
   the repo's code.
2. Add project-specific patterns to that repo's `examples/` as conventions emerge.
3. Use the loop: `/plan` in a fresh session → `/implement <plan>` in another fresh session
   → review → `/retroactive` whenever something slips through.

The machinery itself is stack-neutral — no `package.json`, `tsconfig`, or `pyproject.toml`.
Each project supplies its own verify commands; the AI Layer stays portable.
