# Plan: Document the parallel-implement protocol in piv-loop SKILL.md

## Summary
Add a single **"Parallel implement"** section to `.claude/skills/piv-loop/SKILL.md` that
documents how to run several Issues' `/implement` sessions concurrently and land them safely.
The section codifies a four-step protocol (precondition → pre-flight check → carrier →
serial landing), explains why background sub-agents are *not* the carrier (two verified
environment constraints + no Stop-hook gate for sub-agents), and records the promotion rule
(stays documentation until run manually ~3 times, per CLAUDE.md's promote-after-three rule
and ADR-0005's shape test). This is a **docs-only** change — no new command or skill surface,
no code.

## User Story
As an engineer running multiple Issues at once, I want a written protocol for *when* it's
safe to parallelize and *how* to land N branches without semantic conflicts, so that the
worktree isolation `/implement` already provides is actually usable for parallel work
instead of left to improvisation.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT (documentation) |
| Complexity | LOW |
| Systems affected | `.claude/skills/piv-loop/SKILL.md` (prose only) |
| Issue | #13 |

## Context: why this is safe to build now
Issue #13 was *Blocked by* #11 and #12. Both are now **CLOSED** (verified via `gh issue view`):
- #11 — plan file is copied in as the branch's first commit (per-worktree plan visibility).
  Now realized in `.claude/commands/implement.md:64-83` and recorded as ADR-0014. This is
  what makes "one worktree per plan" actually carry the plan, so the protocol can assume it.
- #12 — `/finish` exists (`.claude/commands/finish.md`) and `/validate` opens the PR. The
  landing chain in step 4 references `/finish`, which now exists.

## The two environment constraints (the subagent rationale)
Stated verbatim in the Issue, verified 2026-06-13. These are *why* the carrier is a real
terminal, not a sub-agent — the section must state both plus the Stop-hook point:
1. **Background sub-agents are effectively read-only** — Write / Bash / `gh` are auto-denied
   for them, so a sub-agent cannot run the mutating steps of `/implement` (branch, commit,
   PR).
2. **Agent-tool worktree isolation snapshots from session-start HEAD** — a plan file
   committed mid-session (which is exactly what `/implement` Phase 2 does, ADR-0014) is
   invisible to a sub-agent spawned after that commit.
3. **No Stop-hook gate for sub-agents** — the `validate_gate` Stop hook that enforces the
   validation floor runs on *session* end, not sub-agent end, so a sub-agent carrier would
   bypass the only hook-enforced gate (see ADR-0009 for why that gate is the floor).

## Patterns to Follow
The target file is short, lean prose with `##` sections, bullet lists, and `→ run /command`
arrows. Mirror that register exactly — do not introduce tables or headings heavier than the
surrounding file unless they improve scannability of the four steps.

```markdown
## The three phases

**Plan** — New session. ... → run `/plan`.

**Implement** — **Reopen a fresh session.** ... → run `/implement <plan-path>`.

**Validate** — **Fresh session.** ... → run `/validate <plan-path>`.

## Rules

- One job per session; prefer `/clear` over compaction between phases.
- ...
- Promote anything you prompt more than three times into a command or skill.
```
`// SOURCE: .claude/skills/piv-loop/SKILL.md:20-46` — section/heading style and the
existing promote-after-three rule the new section's promotion note points back to.

```markdown
### Worktree isolation
... All implementation work (Phases 3–5) happens inside the worktree directory ...
This keeps parallel feature sessions from interfering with each other via branch-switching.
```
`// SOURCE: .claude/commands/implement.md:44-62` — the existing isolation convention the
"Carrier" step inherits rather than re-specifies.

```markdown
The next step is **`/validate <plan-path>`** ... After the PR merges, run **`/finish {branch}`**
```
`// SOURCE: .claude/commands/implement.md:126-133` — the single-Issue landing tail the
"Serial landing" step generalizes to N branches.

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/skills/piv-loop/SKILL.md` | UPDATE | Add the "Parallel implement" section |

## Tasks

### Task 1: Add the "Parallel implement" section to piv-loop SKILL.md
- File: `.claude/skills/piv-loop/SKILL.md`
- Action: UPDATE
- Placement: insert a new `## Parallel implement` section **after the `## Rules` section
  (ends at line 46) and before `## When NOT to use` (line 48)**. Rationale: the reader has
  the single-Issue loop and the Rules (including promote-after-three) in hand; parallel work
  is the scale-out that builds on both, and the promotion note can point back to the rule
  just read. (If the implementer judges placement directly after `## The three phases` reads
  better, that is an acceptable deviation — record it.)
- Implement: write a lean section, matching the file's prose register, that contains all
  four steps and the subagent rationale. Required content, mapped to acceptance criteria:

  1. **Precondition** — each Issue has its own human-reviewed plan from the normal `/plan`
     flow. Parallelism starts from N already-reviewed plans, not N raw Issues.

  2. **Pre-flight check** — before opening parallel sessions, check **two concrete inputs**
     (name both explicitly — AC #2):
     - (a) GitHub **`Blocked by #NN`** links between the Issues.
     - (b) pairwise intersection of the plans' **"Files to Change"** tables.
     Any blocker link or any file overlap → those plans run **serially**, not in parallel.

  3. **Carrier** — **one real interactive terminal session per plan** (tmux panes / terminal
     tabs), each running `/implement <plan>`. Worktree isolation comes from `/implement`
     Phase 2's existing convention (one worktree per branch — do not re-specify it, point to
     it). Blockers are resolved by **asking the human directly**, not by an agent. Then state
     **why sub-agents are NOT the carrier**, citing all three points from "The two
     environment constraints" above (read-only sub-agents; session-start-HEAD snapshot hides
     the mid-session plan commit; no Stop-hook gate for sub-agents). (AC #1 — subagent
     rationale.)

  4. **Serial landing** — implements may run in parallel, but **landing is one branch at a
     time**. Order the chain so **sync-main comes before `/validate`** (AC #3):
     `git merge origin/main` in the worktree (picks up already-merged siblings; semantic
     conflicts surface here) → `/validate` (validates the *combined* state) → PR → human
     merge → `/finish` → next branch. The point of sync-before-validate: each branch is
     validated against the state it will actually merge into, so the Nth landing can't be
     green in isolation yet broken once its siblings are present.

  Then a short **promotion note**: this stays documentation until it has been run manually
  ~3 times; only then consider commandifying it, per CLAUDE.md's promote-after-three rule and
  ADR-0005's shape test (a long interactive multi-session workflow leans skill, not a
  one-shot `$ARGUMENTS` command — so even at promotion time it is not obviously a command).
- Mirror: `.claude/skills/piv-loop/SKILL.md:20-46` (section/prose style),
  `.claude/commands/implement.md:44-62` (isolation convention to reference),
  `.claude/commands/implement.md:126-133` (single-Issue landing tail).
- Constraints (AC #4): **add no new command or skill** — no new file under `.claude/commands/`
  or `.claude/skills/`, no `→ run /newthing` arrow for a command that doesn't exist. The
  only surface touched is this one SKILL.md.
- Keep it lean: the file is intentionally short (CLAUDE.md: "keep it lean"). Aim for a
  section that earns its length — roughly 4 labeled steps + a promotion note, not an essay.
- Validate: `bash .claude/validate.sh` (must stay green — see Validation), then the manual
  checklist below.

## Validation
**Automated** — `bash .claude/validate.sh`. This runs `sync.test.sh`, `unsync.test.sh`, and
`validate_gate.test.sh`; none of them assert on SKILL.md prose, so the bar is **no
regression — the gate must stay green**, confirming the doc edit broke nothing. The
`validate_gate` Stop hook runs this same script on session end.

**Manual (E2E) — read the new section and confirm each, since no automated test covers prose:**
- [ ] Section exists in `.claude/skills/piv-loop/SKILL.md` with all four steps
      (precondition, pre-flight, carrier, serial landing) **and** the subagent rationale. (AC #1)
- [ ] Pre-flight step names **both** concrete inputs verbatim: `Blocked by` links **and**
      "Files to Change" intersection. (AC #2)
- [ ] Serial-landing step orders **`git merge origin/main` before `/validate`** in the
      written chain. (AC #3)
- [ ] **No** new file under `.claude/commands/` or `.claude/skills/`; `git status` shows only
      `SKILL.md` modified. (AC #4)
- [ ] Subagent rationale names all three points (read-only sub-agents, session-start-HEAD
      snapshot, no Stop-hook gate).
- [ ] Promotion note references the promote-after-three rule and ADR-0005's shape test.
- [ ] `git diff --stat` shows exactly one file changed.

## Acceptance Criteria
- [ ] piv-loop SKILL.md gains the section with all four steps and the subagent rationale
- [ ] Pre-flight check names its two concrete inputs (Blocked-by links, Files-to-Change intersection)
- [ ] Serial-landing step explicitly orders sync-main *before* `/validate`
- [ ] No new command/skill surface is added
- [ ] `bash .claude/validate.sh` passes (no regression)
- [ ] Follows the existing lean prose style of the file
