# Plan: fix(piv): plan file becomes the branch's first commit

## Summary
A plan written by `/plan` is an uncommitted draft in the main repo working dir (the
never-commit-to-main invariant forbids committing it there). `/implement` Phase 2 creates
the feature worktree from `main`'s committed state (`.claude/commands/implement.md:51`),
so the plan file is invisible inside the worktree — `/validate`'s worktree-relative
resolution (`.claude/commands/validate.md:25`) then finds nothing, and the archive-on-green
step (`.claude/commands/validate.md:63`) has nothing to move. The fix is documentation-only:
amend `/implement` Phase 2 to (a) exclude untracked `.agents/plans/` drafts from the
"Dirty, on main → STOP" check, and (b) add a final step that copies the plan into the
worktree, commits it as the branch's **first commit**, and deletes the main-repo draft;
then touch up `/validate` so Phase 1 resolution and the Phase 4 archive are explicitly
worktree-relative, with the archive performed as `git mv` + commit on the branch so the
squash-merge carries `completed/{slug}.plan.md` into main. This preserves ADR-0013
(Validate archives on green) — it changes only the *mechanics* (a tracked `git mv` instead
of an untracked file move) so the archive survives the merge.

## User Story
As an implementer agent working inside a feature worktree, I want the plan file to be a
tracked file on my branch from the first commit, so that I can read it, record deviations
into it, and `/validate` can resolve and archive it without any cross-checkout reads.

## Metadata
| Field | Value |
|-------|-------|
| Type | BUG_FIX |
| Complexity | LOW |
| Systems affected | `.claude/commands/implement.md`, `.claude/commands/validate.md` |
| Issue | #11 |

## Root-cause chain (context for the implementer)
1. `/plan` writes `.agents/plans/{slug}.plan.md` as an **uncommitted** file in the main
   repo (`.claude/commands/plan.md:57`); never-commit-to-main (`CLAUDE.md` Do-not) forbids
   committing it there.
2. `/implement` Phase 2 runs `git worktree add -b {branch} ../{repo-dirname}-{branch} main`
   (`.claude/commands/implement.md:51`), which materializes only main's *committed* tree —
   the draft does not exist inside the worktree, yet "All implementation work (Phases 3–5)
   happens inside the worktree directory" (`.claude/commands/implement.md:56-58`).
3. Production evidence: `b37b6f1` (feat/7's implement commit) contains zero `.agents/`
   changes; `457f2ac` repaired that after the fact and was itself a direct-to-main commit.
4. ADR-0013 (`docs/adr/0013-plan-archived-by-validate-on-green-not-implement.md`) fixed
   archive *timing* but not visibility: `/validate` Phase 1 resolves
   `.agents/plans/{slug}.plan.md` relative to CWD (`.claude/commands/validate.md:25`) and
   in a worktree that file still doesn't exist.
5. Historical proof of the fix shape: in feat/01 and feat/03 the plan reached main via the
   feature PR's squash-merge — plans natively live on the branch.

## Patterns to Follow

### Table-row edits in the Phase 2 git-state table
The dirty check is a markdown table row; the fix edits the row's Action cell in place,
matching the existing terse imperative style:

```markdown
<!-- SOURCE: .claude/commands/implement.md:28-33 -->
| State | Action |
|-------|--------|
| Clean, on main, in sync with origin | Create a feature branch (naming below) |
...
| Dirty, on main | STOP — ask the user to stash or commit first |
```

### Worktree-state table + prose follow-up
The worktree section already pairs a 3-row state table with prose guardrails after it
(`.claude/commands/implement.md:47-61`). The new "seed the plan" step should follow the
same shape: numbered/imperative prose immediately after the existing table and the
`git checkout -b` warning (`.claude/commands/implement.md:54`).

### Retroactive-annotation convention
Rules added after an incident carry a `(retroactive: {slug})` tag:

```markdown
<!-- SOURCE: CLAUDE.md:118-119 -->
- Never commit directly to local `main` — ... (A local-only main commit becomes a
  divergence after the next squash-merge — retroactive: fix-unsync-cross-mount.)
```
Use `(retroactive: fix-plan-file-first-commit)` on the new invisibility rule if a tag is
added; keep it short.

### Validate's PASS bullet style
The archive instruction is a `- **PASS**:` bullet (`.claude/commands/validate.md:63-66`);
amend it in place rather than adding a new section.

### Commit-message style for plan/docs commits
History uses `docs(agents): archive plan and add report for fix-unsync-cross-mount`
(`457f2ac`). The seeded first commit should follow: `docs(plan): add {slug} plan`.

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/commands/implement.md` | UPDATE | Phase 2: dirty-check carve-out for untracked `.agents/plans/`; new "seed the plan into the branch" final step; Phase 4 one-line note that the plan is tracked |
| `.claude/commands/validate.md` | UPDATE | Phase 1: state resolution is worktree-relative (plan is tracked on the branch); Phase 4: archive = `git mv` + commit on the branch |

No other files. Hooks and sync scripts are Issue #14's territory — do not touch
`.claude/hooks/`, `scripts/sync*.sh`, or `scripts/unsync*.sh`.

## Tasks

### Task 1: Clarify the dirty check in `/implement` Phase 2
- **File**: `.claude/commands/implement.md`
- **Action**: UPDATE (lines 28-33, the git-state table; specifically the row at line 32)
- **Implement**: Change the `Dirty, on main` row so only **modifications to tracked
  files** block. Untracked files under `.agents/plans/` are the expected state (a plan
  draft awaiting pickup) and must NOT trigger STOP. Suggested wording:

  ```markdown
  | Dirty, on main (tracked files modified) | STOP — ask the user to stash or commit first |
  | On main, only untracked files under `.agents/plans/` | Expected — that's the plan draft awaiting pickup (see "Seed the plan" below); proceed |
  ```

  Keep the other rows untouched.
- **Mirror**: existing table style at `.claude/commands/implement.md:28-33`
- **Validate**: re-read the table; confirm the only STOP-on-dirty trigger is tracked-file
  modifications, and the carve-out names `.agents/plans/` explicitly (Issue AC #2)

### Task 2: Add the "seed the plan into the branch" step to `/implement` Phase 2
- **File**: `.claude/commands/implement.md`
- **Action**: UPDATE (insert after the worktree guardrail paragraphs, i.e. after line 61,
  still inside "### Worktree isolation" or as a sibling `###` heading at the end of
  Phase 2)
- **Implement**: Add a final Phase 2 step, in order:
  1. **Copy** the plan file from the main repo (the `$ARGUMENTS` path resolved in
     Phase 1) into the worktree's `.agents/plans/{slug}.plan.md` (create the directory
     if absent — worktrees materialize only committed paths, and `.agents/plans/` may
     contain nothing tracked).
  2. **Commit it as the first commit on the branch**, from inside the worktree:
     `git add .agents/plans/{slug}.plan.md && git commit -m "docs(plan): add {slug} plan"`.
     This never touches main — the commit lands on `{branch}` inside the worktree.
  3. **Delete the uncommitted draft** from the main repo working dir, only after the
     commit succeeds. Single source: the branch copy is now canonical, so deviations the
     implementer records into the plan (Phase 3 step 5) cannot diverge from a stale draft.
  4. **Idempotence guard** for the "worktree already exists" row
     (`.claude/commands/implement.md:50`): if `.agents/plans/{slug}.plan.md` is already
     tracked on the branch, skip the copy/commit; if a main-repo draft still lingers,
     remove it only when identical to the branch copy, otherwise surface the difference
     to the user instead of silently picking one.

  State the rationale in one sentence (the command file's existing voice explains *why*
  for each guardrail, e.g. lines 54 and 35-38): a worktree materializes only main's
  committed state, so an uncommitted draft is invisible inside it; committing the plan
  first makes it readable by Phase 3, by `/validate`, and carries it to main via the
  PR's squash-merge `(retroactive: fix-plan-file-first-commit)`.
- **Mirror**: prose-guardrail style at `.claude/commands/implement.md:54-61`; commit
  message style from `457f2ac`
- **Validate**: walk the issue's dry-run criterion mentally against the new text — plan
  visible in worktree, first commit is the plan, main repo working dir clean (Issue AC #1
  and #3); confirmed for real in Task 5

### Task 3: Note in `/implement` Phase 4 that the plan is a tracked branch file
- **File**: `.claude/commands/implement.md`
- **Action**: UPDATE (lines 84-90, Phase 4 — the "Leave the plan in `.agents/plans/`"
  sentence at line 88)
- **Implement**: One-line addition, no restructuring: the plan is a **tracked file on the
  branch** (seeded in Phase 2), so deviations recorded into it must be committed on the
  branch like any other change; "leave the plan in `.agents/plans/`" means the
  worktree-relative path — never reach back into the main repo checkout.
- **Mirror**: the existing Phase 4 sentence structure at `.claude/commands/implement.md:88-90`
- **Validate**: confirm the sentence doesn't contradict ADR-0013 (archiving still belongs
  to Validate) — it only changes *where* the plan lives, not *who* moves it

### Task 4: Make `/validate` Phase 1 + Phase 4 explicitly worktree-relative
- **File**: `.claude/commands/validate.md`
- **Action**: UPDATE (two spots: Phase 1 table/prose at lines 21-29; Phase 4 PASS bullet
  at lines 63-66)
- **Implement**:
  1. Phase 1 (after the table, near the "Files are the only durable source" paragraph at
     line 28-29): add one sentence — resolution is relative to the current checkout
     (the feature worktree); the plan is a tracked file on the branch since its first
     commit, so no cross-checkout reads into the main repo are ever needed or allowed.
  2. Phase 4 PASS bullet (line 63): the archive is
     `git mv .agents/plans/{slug}.plan.md .agents/plans/completed/{slug}.plan.md`
     **plus a commit on the branch** (e.g. `docs(plan): archive {slug} plan on green gate`),
     so the squash-merge carries `completed/{slug}.plan.md` into main. Keep the existing
     re-validation skip ("already resolved from `completed/`") untouched — it already
     covers idempotence per ADR-0013.
- **Mirror**: PASS-bullet style at `.claude/commands/validate.md:63-66`; commit-message
  style from `457f2ac`
- **Validate**: trace the full chain on paper: seed commit (Task 2) → Phase 3 deviations
  committed (Task 3) → `/validate` resolves worktree-relative (this task) → `git mv` +
  commit → squash-merge lands `completed/{slug}.plan.md` on main (Issue AC #4)

### Task 5: Dry-run walkthrough (verification only — no repo changes)
- **File**: none (scratch environment)
- **Action**: VERIFY
- **Implement**: In a throwaway clone (e.g. `git clone /home/dylan/Documents/ai-layer-template /tmp/alt-dryrun`),
  follow the amended Phase 2 text literally:
  1. Create a fake plan draft `.agents/plans/demo.plan.md` (uncommitted) in the clone.
  2. Confirm the amended dirty-check text classifies this state as "proceed".
  3. `git worktree add -b feat/99-demo ../alt-dryrun-feat99 main`; confirm the plan is
     absent in the worktree (reproduces the bug).
  4. Execute the seed step: copy → commit → delete draft.
  5. Assert: `git -C ../alt-dryrun-feat99 log --oneline` shows the plan commit as the
     branch's only commit past main; `git -C /tmp/alt-dryrun status` is clean;
     `.agents/plans/demo.plan.md` exists inside the worktree.
  6. Simulate validate-on-green: `git mv` to `completed/`, commit, then
     `git merge --squash feat/99-demo` onto a scratch branch and confirm
     `completed/demo.plan.md` survives the squash.
  7. Tear down: remove the worktree and `/tmp/alt-dryrun`.
- **Mirror**: N/A
- **Validate**: every assertion in step 5-6 holds (Issue AC #3 and #4)

## Validation
```bash
bash .claude/validate.sh   # sync.test.sh + unsync.test.sh — untouched by this change, must stay green
```
E2E checklist:
- [ ] `implement.md` Phase 2 contains the copy + first-commit + delete-draft step, with
      the idempotence guard for pre-existing worktrees
- [ ] `implement.md` Phase 2 dirty-state table explicitly excludes untracked
      `.agents/plans/` files from STOP
- [ ] Task 5 dry-run: plan visible in worktree, first commit is the plan, main repo
      working dir clean afterwards, `completed/{slug}.plan.md` survives a squash-merge
- [ ] `validate.md` Phase 1 resolution and Phase 4 archive read worktree-relative with no
      cross-checkout reads; archive is `git mv` + commit on the branch
- [ ] `grep -n "\.agents/plans" .claude/commands/*.md CLAUDE.md docs/adr/0013-*.md` —
      no remaining text implies the plan is readable from the main repo during
      Implement/Validate, and nothing contradicts ADR-0013

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors (`bash .claude/validate.sh`)
- [ ] Follows existing patterns (table-row edits, prose guardrails with rationale,
      retroactive tag, `457f2ac` commit-message style)
- [ ] End-to-end behavior verified via the Task 5 dry-run
- [ ] No changes to hooks or sync scripts (Issue #14 territory)

## Risks / Assumptions
- **Assumption — slug consistency**: `/validate` blank-input inference derives the slug
  from the branch name (`.claude/commands/validate.md:25`), so the plan filename slug must
  match the branch slug. This is existing behavior, unchanged here; the seed step copies
  the file under its original name.
- **Assumption — no new ADR**: this fix extends ADR-0013's mechanics (archive becomes a
  tracked `git mv` on the branch) without changing its decision (Validate archives on
  green). A one-line amendment to ADR-0013 was considered and deliberately left out to
  stay surgical; if the reviewer wants the mechanics recorded, that is a `/retroactive`
  follow-up, not part of this change.
- **Risk — draft divergence on resumed worktrees**: if a session dies between worktree
  creation and the seed commit, both a main-repo draft and an unseeded worktree exist.
  The Task 2 idempotence guard covers the committed case; the half-done case resolves
  naturally because re-running Phase 2 finds the worktree (row 1 of the worktree table)
  and the seed step then runs on the still-present draft.
- **Risk — CLAUDE.md Do-not wording**: the existing Do-not bullet (`CLAUDE.md:119`) says
  the implementer "must leave the plan in `.agents/plans/`" — still true worktree-relative,
  so no CLAUDE.md edit is planned. If the reviewer reads it as ambiguous, a one-line
  clarification there is the only candidate scope extension.
