---
description: Run the full validation gate (project verify commands + E2E) as its own PIV session
argument-hint: <path/to/plan.md | blank to use current branch>
---

# Validate

This is the **Validate** phase of the [PIV Loop](../skills/piv-loop/SKILL.md). Open it in a
**fresh session** — the only input is either a plan path or the current branch name.

The validate gate `Stop` hook (`validate_gate.py`) enforces a green floor automatically at
every session end. This command is the *deliberate* full pass: it runs the same gate plus
the plan's E2E checklist and serves as the entry to human review and the System Evolution
handoff.

---

## Phase 1 — Resolve the plan

Resolve which plan to validate via a three-tier contract:

| Input | Action |
|-------|--------|
| Plan path given (`$ARGUMENTS`) | Use it directly; read its E2E section |
| Blank | Infer from current branch `feat/{NN}-{slug}`: try `.agents/plans/{slug}.plan.md`, then fall back to `.agents/plans/completed/{slug}.plan.md` (a re-validation after a prior pass) |
| No plan found | Run the mechanical gate only; state "no plan — E2E skipped" |

**Files are the only durable source.** Never infer E2E steps from the conversation — only
from the plan file. If no plan exists, say so explicitly rather than guessing.

Resolution is relative to the current checkout (the feature worktree). The plan is a
tracked file on the branch since its first commit (`/implement` Phase 2 seeds it); no
cross-checkout reads into the main repo are ever needed or allowed.

## Phase 2 — Run the mechanical gate

Run the project's verify commands as listed in `CLAUDE.md → Verify commands` (or execute
`.claude/validate.sh` directly if present). Report **PASS / FAIL per command**, then an
**Overall** result.

```
[PASS] bash .claude/validate.sh
Overall: PASS
```

On any failure: fix the root cause and re-run before proceeding. Do not move to E2E with a
red gate.

## Phase 3 — Run E2E (if a plan was found)

Re-read the plan's `## Validation` section (or equivalent E2E section) and run each step as a checklist. Confirm every outcome
matches the plan. Fix and re-run on failure.

If the plan has no E2E section, do a smoke test of the changed behavior and note "no E2E
section in plan — smoke test only."

## Phase 3.5 — Re-execute changed operator checks

Runs **regardless of whether a plan was found** — an operator runbook can ship without an
E2E plan section. A runbook/operator-card grounding block is free-floating prose that
`validate.sh` never touches; a pasted `# → observed:` comment is a *claim*, not evidence.
**The gate re-runs it, it does not re-read it.**

1. **Enumerate.** List every operator runbook / operator-card **added or changed on the
   branch**:
   `git diff --name-only main...HEAD -- '.agents/reports/*runbook*.md' '.agents/**/*operator*.md'`
   (nothing changed → this phase is a no-op; say so).
2. **Re-run each grounding/check block.** For every "Grounding evidence" / GO-checklist /
   check-command block in those files, actually execute the known-good **and** known-bad
   cases. Treat any pasted `# → observed:` as **unverified until reproduced**.
3. **Prove the known-bad executed — don't infer it from output.** Requiring the two outputs
   to *differ* is not enough: #81's cases diverged (`62 → (empty)`) yet were forged — the
   known-bad's empty output came from an exec-failure (broken shebang → rc 127) that
   `|| true`/`2>/dev/null` swallowed, coinciding with its *expected* value while never
   running. So assert the known-bad actually **ran**: run the fake directly and confirm a
   real return code (rc 0, not 127), not just that its output looks right. A case that reaches
   its expected result by never executing is **forged**, however the two outputs compare.
4. **Launch/operational commands count too — a missing grounding block is the finding.** A
   start/cron/daemon command block is not exempt just because it carries no `# → observed:`
   line; its *absence* is the miss (§4 of the loop runbook shipped an unguarded `*/5` cron
   exactly this way). Any command a scheduler re-enters (a cron `drain`) must carry its
   concurrency guard — `flock` for a tick that can outlast its interval — **and** a grounding
   block proving the guard no-ops on contention; re-run that block here like any check.

**FAIL the gate** if any documented check cannot be re-run, does not flip, can't prove the
known-bad actually executed, or a launch/operational command lacks its re-entrancy guard and a
re-run grounding block. This is the mechanical enforcement of the Verification-led rule — prose forbade
shipping unrun checks twice (retroactives `verify-check-commands`, `validate-reexec-operator-checks`)
and it still recurred, so the gate now re-executes rather than trusting the page.

## Phase 4 — Report

Write the final result:

```
Gate:      PASS / FAIL
E2E:       PASS / FAIL / SKIPPED (no plan)
Op-checks: PASS / FAIL / N/A (no runbook/operator-card changed)
Overall:   PASS / FAIL
```

- **PASS**: archive the plan with
  `git mv .agents/plans/{slug}.plan.md .agents/plans/completed/{slug}.plan.md`
  then commit on the branch **with the Phase 4 result block in the commit body**, so the
  archive carries verifiable evidence it was a Validate-session pass. The subject line alone
  cannot distinguish a legitimate archive from an implementer self-archiving in the implement
  flow (both read "archive … on green gate"); the embedded gate/E2E results can — a reviewer
  reads them straight from `git log`, and a bare subject with no block is now the smell.
  ```
  git commit -m "docs(plan): archive {slug} plan on green gate" -m "$(cat <<'EOF'
  Validate session result:
  Gate:      PASS  (bash .claude/validate.sh)
  E2E:       PASS  /  SKIPPED (no plan E2E section)
  Op-checks: PASS  /  N/A (no runbook/operator-card changed)
  Overall:   PASS
  EOF
  )"
  ```
  Fill the block with the **actual** Phase 4 results, never a template — a fabricated PASS is
  now a visible lie in the history, not an ambiguous default. This is the point a plan becomes
  "completed" (a green gate, not implementation's end); the squash-merge carries
  `completed/{slug}.plan.md` into main. If the plan was already resolved from `completed/`
  (a re-validation), it is already archived — skip the move. Then the tree is ready for human
  review → merge.
- **FAIL**: list every failing check with its error. Fix, re-run, achieve PASS before
  declaring done. Leave the plan in `.agents/plans/` — a failing gate is not "completed".

## Phase 5 — Push, open PR, and hand to human review

On PASS:

1. **Push the branch** (from inside the feature worktree):
   `git push -u origin {branch}`
2. **Open the PR**:
   ```
   gh pr create \
     --title "{short title from plan summary}" \
     --body "$(cat <<'EOF'
   ## Summary
   {plan summary paragraph}

   ## 變更說明
   {Traditional Chinese: what changed and why}

   ## Report
   `.agents/reports/{plan-name}-report.md`

   Closes #{N}
   EOF
   )"
   ```
   Include `Closes #{N}` only when the plan carries an Issue number. Pull the summary from
   the plan's `## Summary` section and the report path from
   `.agents/reports/{plan-name}-report.md`.

   **Comprehension floor (every PR).** The PR body **must** always include a `## 變更說明`
   section in Traditional Chinese — what changed and why, in the author's language. This is
   the author's comprehension checkpoint at the human gate, enforced by the author's PR review
   here, **not** by CI (see ADR-0022; a CI gate was retracted as over-design and is
   unenforceable on a free-private repo). Canonical-doc PRs (`CONTEXT.md`, `docs/adr/`) are
   the strongest case — those stay English for zero-drift, so the TC summary is the author's
   only language bridge — but the floor applies to every PR, not just canonical-doc ones.
3. **Share the PR URL** with reviewers.
4. **Signal PASS** (best-effort — never gate the PR flow on it):
   `bash .claude/hooks/notify.sh pass "Validate PASS" "{branch}: PR ready"`. This rings the
   bell — flagging the agent's tmux window, which tmux clears when you visit it — and, if a
   topic is configured, pushes to the operator's phone. PASS is emitted only here, in a real
   validate session — the deliberate asymmetry to the FAIL path, which the `validate_gate.py`
   Stop hook fires deterministically in *any* session (see ADR-0021).

**Review-fix loop** — if reviewers request changes: open a fresh session inside the feature
worktree, address the comments, re-run `/validate` (which falls back to `completed/` for
re-validation — the archive step is idempotent), then push the update with `git push`.

**Successor**: after the PR merges, run `/clean-worktree {branch}` in a fresh session from the main
repo to pull main up to date, remove the worktree, and delete the local and remote branch.

When human review surfaces a **problem** (a bug that reached the codebase, a class of
miss the AI Layer should have caught), the System Evolution outer loop is triggered through
the workflow: end the review by routing to `/retroactive` in a fresh session. Frame it as
surfacing the option — whether to actually run a retroactive stays judgment (severity ×
recurrence). See [system-evolution](../skills/system-evolution/SKILL.md) and ADR-0010.

This mirrors how `/implement` hands off to `/validate`: each phase deterministically names
its successor, so the workflow routes correctly without relying on the agent's memory.
