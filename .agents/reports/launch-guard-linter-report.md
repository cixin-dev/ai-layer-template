# Implement Report: Deterministic launch-guard linter (#96)

**Branch**: `feat/96-launch-guard-linter` (worktree off `main` @ c3f77d7)
**Plan**: `.agents/plans/launch-guard-linter.plan.md` (first commit e8920cd)
**Result**: all tasks complete; full gate green (rc 0).

## Tasks completed
| # | Task | Status |
|---|------|--------|
| 1 | `scripts/launch_guard_check.test.sh` — 6-case grounding seam (RED first) | ✅ |
| 2 | `scripts/launch_guard_check.sh` — detector greens the seam + passes real tree | ✅ |
| 3 | Stage exec bit `100755` on both scripts (`git update-index --chmod=+x`) | ✅ |
| 4 | Wire `launch_guard_check.sh` into `.claude/validate.sh` | ✅ |

## Files changed
- **CREATE** `scripts/launch_guard_check.sh` (100755) — detector.
- **CREATE** `scripts/launch_guard_check.test.sh` (100755) — grounding seam.
- **UPDATE** `.claude/validate.sh` — one line: `bash "$dir/launch_guard_check.sh" || rc=1` after `piv_check`.
- (committed) `.agents/plans/launch-guard-linter.plan.md` — seeded as branch's first commit.

## Tests written (seam: 6 cases, all green)
1. known-good — flock-guarded `*/5` in ` ```cron ` → rc 0, "passed".
2. known-bad — unguarded `*/5` in ` ```cron ` → asserts rc **exactly 1** (not 127, no forged flip) + names the file + says "unguarded".
3. escape-hatch (reason) — `# linter:allow-unguarded-cron: <reason>` above the line → rc 0, reported "allowed" + reason printed.
4. bare-marker-still-fails — reasonless `# linter:allow-unguarded-cron` → rc **exactly 1** (reason requirement binds).
5. out-of-scope-not-flagged — persistent `bash … &` in a ` ```bash ` fence + unguarded `*/5` in inline prose (both outside any ` ```cron ` fence), file named `notes.md` not "runbook" → rc 0.
6. non-git dir → rc 0 (fail open).

## Validation results
- **Seam**: `bash scripts/launch_guard_check.test.sh` → `All tests passed.` (rc 0).
- **Full gate**: `bash .claude/validate.sh` → rc 0 (exec-bit + PIV + launch-guard all pass); pass output ends with the scope-boundary line.
- **exec-bit gate**: both new scripts staged `100755`; `exec_bit_check.sh` still green.
- **Live E2E catch** (done live, not reasoned): a *tracked* scratch `*.md` cycled —
  - unguarded ` ```cron ` `*/5` → **rc 1**, offender named (`e2e_scratch.md:3`).
  - + reasoned `# linter:allow-unguarded-cron: <why>` → **rc 0**, reported "allowed" with reason.
  - reason stripped to a bare marker → **rc 1** again.
  - scratch then removed (`git rm -f`); tree clean.
- **Scope proof**: the real `.agents/reports/night-shift-loop-runbook.md:89-90` ` ```cron ` line is the tree's only real fence candidate and is `flock`-guarded → not flagged; the runbook's persistent `bash … &` is not a candidate.

## Deviations from plan (with rationale)
1. **Base git state differed from the plan's Phase-2 assumption.** The checkout was on an *unrelated* feature branch `docs/clone-pointer-adr0027` with uncommitted work (dashboard.md, CONTEXT.md, ADR-0027) — not a clean `main`. Per the plan's "branch off current `main`" note, I created the worktree from the **`main` ref** (not the current branch), so #96 does not inherit or disturb that unrelated in-progress work. `origin/main..main` tripwire was empty (invariant intact). No content deviation — same base the plan intended.
2. **Test case-3 assertion loosened to case-insensitive.** Detector prints the exemption section header as "**A**llowed exemptions"; the test originally grepped lowercase `"allowed"`. Behavior was correct (rc 0, reason printed); the plan spec says "reports it as `allowed`", so I aligned the grep to `-qi` rather than change correct output. Reason text is still asserted verbatim.
3. **Runbook path note (not a behavior change).** Plan referenced `night-shift-loop-runbook.md:90`; the file actually lives at `.agents/reports/night-shift-loop-runbook.md` (fence open line 89, cron line 90). Confirmed flock-guarded.

## No CLAUDE.md change
As the plan specified: the gate lets the existing `launch-command-grounding` prose lean on a mechanical backstop; `/validate` Phase 3.5 item 4 stays (covers recognition on any branch + the out-of-scope launch surfaces the gate deliberately excludes).

## Next
`/validate .agents/plans/launch-guard-linter.plan.md` in a fresh session → full gate + E2E + human review → PR (body needs a `## 變更說明`). After merge: `/clean-worktree feat/96-launch-guard-linter`.
