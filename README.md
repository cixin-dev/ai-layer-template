# AI Layer Template

A language-agnostic, drop-in **AI Layer** for any codebase: the versioned set of rules,
commands, skills, and examples that tells Claude Code how to think, work, and verify in a
project. It encodes a small set of battle-tested ideas from agentic-engineering practice so
you don't have to re-derive them per project.

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
│       ├── system-evolution/SKILL.md
│       └── tdd-gate/SKILL.md
├── examples/
│   └── deep-module-pattern.md      # on-demand context: a pattern to mirror
├── scripts/
│   └── install.sh                  # copy the AI Layer into a project
└── README.md
```

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

## After installing

1. Open `CLAUDE.md` and fill in the **Project specifics** section (stack, the project's
   verify commands, architecture, known footguns). Keep it lean.
2. Add project-specific patterns to `examples/` as conventions emerge.
3. Use the loop: `/plan` in a fresh session → `/implement <plan>` in another fresh session
   → review → `/retroactive` whenever something slips through.

This template is intentionally stack-neutral — there's no `package.json`, `tsconfig`,
`pyproject.toml`, or other tooling. Each project supplies its own commands; the AI Layer
stays portable.
