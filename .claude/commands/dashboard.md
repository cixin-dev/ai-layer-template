---
description: Show project development dashboard — open GitHub issues/PRs, plans ready to implement, untracked designs, and active worktree PIV phases with validate verdicts
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

## Phase 2 — Resolve design linkage

For each file found in Phase 1B (both PRDs and plans), resolve its link to a GitHub issue, then
classify it.

**Find the linked issue (in priority order):**

1. **Canonical metadata row.** Grep the *whole* file (not a fixed line window — the row can sit
   below a long summary) for the `| Issue | {value} |` row that `/plan` emits. If the value is a
   `#N` (not `N/A`), that `N` is the linked issue. This is the authoritative signal.
2. **Title fallback** (only when the row is absent or `N/A`): match the file's H1 heading — minus a
   leading `Plan: ` / `PRD` prefix — against the open issue titles (case-insensitive). A clear
   match resolves the issue number.

Do **not** match on the filename slug — plan slugs (`course-field-resolver-family`) rarely appear
in the prose issue title ("Name the third Course-Field resolver…"), so filename matching produces
false "untracked" verdicts. Ignore stray `#N` mentions elsewhere in the body (e.g. a
"Cross-Issue Coordination (#29)" note) — only the canonical row or the H1 title resolves the link.

**Classify each file:**

| Condition | Bucket |
|-----------|--------|
| A `*.plan.md` whose linked issue is **open** | **Ready to Implement** — capture the issue #, its title, and the plan's repo-relative path |
| Any file with **no** linked issue (no `#N` row, no title match) | **Untracked Designs** |
| A file linked only to a **closed** issue | Omit — its work is already tracked/done |

Only `*.plan.md` files are eligible for Ready to Implement — `/implement` operates on plan files;
bare `.md` PRD/backlog drafts go to Untracked when unlinked.

---

## Phase 3 — Resolve worktree PIV phase

For each active worktree (non-main):

| Files present in worktree | Phase |
|---------------------------|-------|
| No `.agents/plans/` or no plan file | `PLAN` |
| Plan file, no matching report | `IMPLEMENT` |
| Plan file + matching report | `VALIDATE` |

If the branch name follows `feat/{N}-{slug}`, extract `{N}` as the linked Issue number.

**Resolve the Validate verdict.** The phase above is inferred from file presence — a report
existing does *not* mean `/validate` ran or passed. Since the plan-archive commit now embeds an
auditable result block (see `chore(validate): embed gate/E2E result block`), read the real verdict
from that worktree's git log:

```bash
git -C {worktree-path} log -1 --grep='plan on green gate' --format='%B'
```

The archive commit body carries an `Overall:` line. Map it to the Validate column:

| Archive commit | Validate |
|----------------|----------|
| Found, `Overall: PASS` | `✅ PASS` |
| Found, `Overall:` present but not `PASS` | `❌ FAIL` |
| No archive commit yet (validate hasn't recorded a verdict) | `—` |

---

## Phase 4 — Render dashboard

Print this structure. Use `(none)` for empty sections.

```
# 📊 Project Dashboard

## Open Issues (N)
| #  | Title                  | Labels        | Assignee |
|----|------------------------|---------------|----------|
| 42 | ...                    | ...           | ...      |

## Open PRs (N)
| #  | Title                  | Branch               | Review   | Draft |
|----|------------------------|----------------------|----------|-------|
| 7  | ...                    | feat/42-...          | APPROVED | no    |

## Ready to Implement (N)
Plans in .agents/plans/ linked to an open issue, awaiting pickup:
| Issue | Title                  | Run                                       |
|-------|------------------------|-------------------------------------------|
| #42   | ...                    | /implement .agents/plans/some.plan.md     |

## Untracked Designs
Files in .agents/prds/ or .agents/plans/ (main, not completed/) with no linked GitHub issue:
- [prds] phase-1-machinery.prd.md — "PRD — Phase 1 Machinery (...)"
- [plans] some-draft.plan.md — "Plan: ..."

## Active Worktrees — PIV Progress
| Worktree                       | Branch              | Issue | Phase     | Validate |
|--------------------------------|---------------------|-------|-----------|----------|
| ../ai-layer-template-feat42-.. | feat/42-some-feat   | #42   | IMPLEMENT | —        |
| ../ai-layer-template-feat26-.. | feat/26-spike       | #26   | VALIDATE  | ✅ PASS  |
```

End with a one-line summary: total open issues, open PRs, plans ready to implement, untracked
designs, and active worktrees.
