---
description: Show project development dashboard — open GitHub issues/PRs, PRDs not yet in tracker, and active worktree PIV phases
---

# Dashboard

Render a real-time read-only snapshot of project development state. No side effects.

---

## Phase 1 — Gather data (run in parallel)

**A. GitHub state**

```bash
gh issue list --state open --json number,title,labels,assignees --limit 50
gh pr list  --state open --json number,title,headRefName,isDraft,reviewDecision --limit 20
```

**B. Local designs (PRDs + plans)**

Scan both directories — exclude `README.md` and any `completed/` subdirectory:
- `.agents/prds/` — PRD files
- `.agents/plans/` — plan files not yet in a worktree branch (i.e. uncommitted drafts sitting in main)

**C. Active worktrees**

```bash
git worktree list --porcelain
```

For each worktree that is **not** the main repo root:
- Extract branch name and absolute path
- List `.agents/plans/*.plan.md` inside it to find the plan slug
- List `.agents/reports/` to check for a `{slug}-report.md`

---

## Phase 2 — Resolve untracked designs

For each file found in Phase 1B (both PRDs and plans):

1. Read the first 30 lines and extract any `#N` GitHub issue reference.
2. Cross-reference against the open issue list from Phase 1A.
3. Mark the file **untracked** when both conditions hold:
   - No `#N` reference found in its header, **and**
   - No open issue title contains the file's base filename (minus extension).

---

## Phase 3 — Resolve worktree PIV phase

For each active worktree (non-main):

| Files present in worktree | Phase |
|---------------------------|-------|
| No `.agents/plans/` or no plan file | `PLAN` |
| Plan file, no matching report | `IMPLEMENT` |
| Plan file + matching report | `VALIDATE` |

If the branch name follows `feat/{N}-{slug}`, extract `{N}` as the linked Issue number.

---

## Phase 4 — Render dashboard

Print this structure. Use `(none)` for empty sections.

```
╔══════════════════════════════════════════════╗
║           PROJECT DASHBOARD                  ║
╚══════════════════════════════════════════════╝

## Open Issues (N)
| #  | Title                  | Labels        | Assignee |
|----|------------------------|---------------|----------|
| 42 | ...                    | ...           | ...      |

## Open PRs (N)
| #  | Title                  | Branch               | Review   | Draft |
|----|------------------------|----------------------|----------|-------|
| 7  | ...                    | feat/42-...          | APPROVED | no    |

## Untracked Designs
Files in .agents/prds/ or .agents/plans/ (main, not completed/) with no linked GitHub issue:
- [prds] phase-1-machinery.prd.md — "PRD — Phase 1 Machinery (...)"
- [plans] some-draft.plan.md — "Plan: ..."

## Active Worktrees — PIV Progress
| Worktree                       | Branch              | Issue | Phase     |
|--------------------------------|---------------------|-------|-----------|
| ../ai-layer-template-feat42-.. | feat/42-some-feat   | #42   | IMPLEMENT |
```

End with a one-line summary: total open issues, open PRs, untracked designs, and active worktrees.
