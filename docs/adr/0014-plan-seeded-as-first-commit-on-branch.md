# Plan seeded as the branch's first commit

The PIV plan file is committed onto the feature branch as its first commit by `/implement`
Phase 2, immediately after the worktree is created. The commit lands inside the worktree —
never on main — and the uncommitted draft in the main repo is deleted once the commit
succeeds. The branch copy is the single canonical source from that point forward.

## Why

`/plan` writes the plan file as an uncommitted draft in the main repo checkout. A worktree
created from main (`git worktree add -b {branch} ... main`) materialises only main's
*committed* state — the draft is invisible inside the worktree. All Phase 3–5 work, and
`/validate`'s plan resolution (ADR-0013), runs inside the worktree, so without this seed
step the plan is unreachable for the entire Implement and Validate phases.

Two alternatives were rejected:

- **Cross-checkout reads** (Phase 3 reads the plan from the main repo path). Breaks the
  worktree-isolation model and requires the agent to track two checkouts simultaneously;
  also ruled out explicitly by CLAUDE.md ("never reach back into the main repo checkout").
- **Copy without committing**. The file would again be invisible after a `git checkout` or
  a fresh session that re-enters the worktree, and `/validate`'s `git mv` archive
  (ADR-0013) cannot stage an untracked file.

Committing the plan as the first branch commit makes it readable by Phase 3, recordable
(deviations committed like any other change), resolvable by `/validate`, and carried to
main via the PR's squash-merge — the same path historical plans took in feat/01 and feat/03.

## Relationship to ADR-0013

ADR-0013 records *when* the plan is archived (Validate-on-green). This ADR records *where*
the plan lives during the PIV Loop (tracked on the branch since its first commit) and *how*
it gets there. The two decisions are adjacent but distinct: ADR-0013's archive step becomes
a `git mv` + commit on the branch so the squash-merge carries `completed/{slug}.plan.md`
into main.
