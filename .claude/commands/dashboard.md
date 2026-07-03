---
description: Show project development dashboard — open GitHub issues/PRs, plans ready to implement, untracked designs, active worktree PIV phases with validate verdicts, and Night Shift loop state (phase + attempts)
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

**D. Night Shift loop state**

The durable per-task loop state lives in `.night-shift/*.state`. Because the executor runs in its
**own clone** (ADR-0024), that state lives *outside* this checkout. The durable way to locate it is
the **`clone pointer`** — the executor publishes its clone's path for observers to read (ADR-0027);
**until Task 2 implements that**, the block below uses an **interim convention guess**
(`~/night-shift/<repo>/`, `<repo>` from this repo's `origin`) — *not* a documented path (ADR-0024
documents the own-clone, **not** this layout). Known limitation this interim keeps: if the clone is
ever off-convention it **silently** falls back to an empty in-checkout `.night-shift` and renders
`(none)` for a *live* loop — the false-negative ADR-0027 removes. An explicit `NIGHT_SHIFT_STATE_DIR`
overrides. This section renders `(none)` when the resolved directory is empty. A single dir is shown
— if multiple Night Shift clones ever run concurrently (#63), only the resolved clone is visible
here.

```bash
# loop_state.sh resolves the dir from NIGHT_SHIFT_STATE_DIR, so export it once and the glob
# and the accessors agree. The executor runs in its OWN clone (ADR-0024); the durable way to
# locate it is the clone pointer (ADR-0027), which Task 2 implements. Until then this is an
# INTERIM convention guess — ~/night-shift/<repo>/, <repo> from THIS repo's origin — NOT a
# documented path; if the clone is off-convention it silently falls back to the in-checkout
# dir (the false-negative ADR-0027 removes). An explicit NIGHT_SHIFT_STATE_DIR still wins.
if [ -z "${NIGHT_SHIFT_STATE_DIR:-}" ]; then
  _ns_repo="$(basename -s .git "$(git remote get-url origin 2>/dev/null)" 2>/dev/null)"
  _ns_conv="$HOME/night-shift/${_ns_repo}/.night-shift"
  if [ -n "$_ns_repo" ] && [ -d "$_ns_conv" ]; then
    NIGHT_SHIFT_STATE_DIR="$_ns_conv"
  else
    NIGHT_SHIFT_STATE_DIR=".night-shift"
  fi
fi
export NIGHT_SHIFT_STATE_DIR
for f in "$NIGHT_SHIFT_STATE_DIR"/*.state; do
  [ -e "$f" ] || continue                       # no files -> section renders (none)
  n="$(basename "$f" .state)"
  printf '%s\t%s\t%s\t%s\n' "$n" \
    "$(bash scripts/loop_state.sh get-phase "$n")" \
    "$(bash scripts/loop_state.sh get-attempts "$n")" \
    "$(bash scripts/loop_state.sh get-escalated "$n")"
done
```

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

## Phase 4 — Classify Night Shift loop state

Using the Phase 1D fields (task id, phase, attempts, escalated) and the Phase 1A open-issue /
open-PR lists, classify each task. Evaluate top-down; use the first matching row.

| Condition (top-down) | Bucket / Status |
|----------------------|-----------------|
| Issue `N` **not** in the open-issues list | **Resolved** — omit from the table (state is stale after merge/close); count in the `(M resolved)` summary tally |
| `escalated = 1` | **🔴 escalated** — terminal; needs human triage |
| An open PR exists whose `headRefName` matches `feat/{N}-*` | **✅ PR open #{pr}** — terminal; awaiting merge |
| otherwise (issue open, not escalated, no matching PR) | **⏳ in-flight** — show live phase + attempts |

**Accepted limitation — ⏳ can't distinguish live from stalled.** A task that hit the retry cap
without escalating, or whose loop crashed, stays issue-open / `escalated=0` / no-PR / `.state`-present
— indistinguishable from a live task; it renders ⏳ in-flight indefinitely (the store carries no
cap-hit / stall signal). A staleness cue (attempts ≥ MAX, or `.state` mtime) is a later
enhancement.

**Accepted limitation — `gh` list limits.** `gh issue/pr list` limits (50/20) could omit a live
task on a very large board, misclassifying it as resolved. Inherits the existing dashboard's limits
and noted here; not fixed in this observability slice.

---

## Phase 5 — Render dashboard

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

## 🌙 Night Shift — Loop State (N)
Durable per-task loop state (.night-shift/*.state; auto-resolved from the executor's clone by
convention — ~/night-shift/<repo>/ — or an explicit NIGHT_SHIFT_STATE_DIR override). In-flight
tasks show their live phase; terminal tasks are marked. Phase shown UPPER-CASED. (none) when empty.
| Task | Phase     | Attempts | Status                |
|------|-----------|----------|-----------------------|
| #42  | IMPLEMENT | 1        | ⏳ in-flight          |
| #57  | VALIDATE  | 0        | ✅ PR open #83        |
| #99  | VALIDATE  | 3        | 🔴 escalated — triage |
```

End with a one-line summary: total open issues, open PRs, plans ready to implement, untracked
designs, active worktrees, and N night-shift tasks in flight (M resolved).
