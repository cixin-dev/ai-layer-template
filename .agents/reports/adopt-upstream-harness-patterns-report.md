# Report: adopt-upstream-harness-patterns

**Branch**: `feat/adopt-upstream-harness-patterns`
**Plan**: `.agents/plans/completed/adopt-upstream-harness-patterns.plan.md`

## Tasks completed

- ✅ **Task 1** — `.claude/hooks/validate_gate.py` + `.claude/hooks/security_guard.py` (generic active hooks)
- ✅ **Task 2** — `.claude/validate.sh` (this repo's dogfood gate: runs `sync.test.sh`)
- ✅ **Task 3** — `scripts/sync.sh` (hooks symlink loop + additive settings.json merge + `--dry-run` support + updated header)
- ✅ **Task 4** — `scripts/sync.test.sh` (new assertions d–h: hook links, settings merge, idempotency, dry-run purity)
- ✅ **Task 5** — `.claude/commands/validate.md` (new Phase-2 `/validate` command)
- ✅ **Task 6** — `.claude/commands/implement.md` (removed Phase 4 full gate + E2E; renumbered; added `/validate` handoff)
- ✅ **Task 7** — `.claude/skills/piv-loop/SKILL.md` + `CLAUDE.md` (Validate reframed as own session); `CONTEXT.md` verified present and consistent
- ✅ **Task 8** — `docs/adr/0009-enforce-validate-gate-by-hook-and-split-validate-step.md`
- ✅ **Task 9** — `README.md` (layout, sync section, "after syncing" loop); `examples/hooks/` (README + 3 reference files)

## Files changed

| File | Action |
|------|--------|
| `.claude/hooks/validate_gate.py` | CREATE |
| `.claude/hooks/security_guard.py` | CREATE |
| `.claude/validate.sh` | CREATE |
| `.claude/commands/validate.md` | CREATE |
| `examples/hooks/README.md` | CREATE |
| `examples/hooks/stop_validate.py` | CREATE |
| `examples/hooks/post_tool_use_lint.py` | CREATE |
| `examples/hooks/security_guard.py` | CREATE |
| `docs/adr/0009-enforce-validate-gate-by-hook-and-split-validate-step.md` | CREATE |
| `scripts/sync.sh` | UPDATE |
| `scripts/sync.test.sh` | UPDATE |
| `.claude/commands/implement.md` | UPDATE |
| `.claude/skills/piv-loop/SKILL.md` | UPDATE |
| `CLAUDE.md` | UPDATE |
| `README.md` | UPDATE |

## Validation results

- Shell syntax: `bash -n scripts/sync.sh scripts/sync.test.sh .claude/validate.sh` → OK
- Python syntax: `python3 -c "import ast,sys;[...]"` over all `.py` hook files → OK
- Behavioral fixtures (validate_gate): stop_hook_active passthrough, fail-open when absent, block on exit-1, silent on exit-0 → all pass
- Behavioral fixtures (security_guard): `.env` deny, `.env.example` allow, `rm -rf` deny → all pass
- `bash scripts/sync.test.sh` (including new assertions d–h) → `All tests passed.`
- Dry-run into temp home: lists `would link:` for both hooks + `would wire hook` for Stop & PreToolUse; creates nothing
- `CONTEXT.md` verified: validate gate entry present, `/validate` session framing consistent, no stale "checks ran during Implement" framing

## Deviations from plan

- **Worktree**: `git worktree add` failed because `feat/adopt-upstream-harness-patterns` was the current branch of the main repo. Worked directly in the main repo checkout (which IS the worktree for this branch). No functional deviation.
- **`CONTEXT.md`**: Verified-only per plan instruction (already authored in alignment session). No edits needed — consistent with final code.

## Tests written

`scripts/sync.test.sh` assertions added:
- **(d)** hooks appear as `would link:` in dry-run
- **(e)** `would wire hook` in dry-run, no `settings.json` created
- **(f)** real run creates hook symlinks and `settings.json` with both hook commands
- **(g)** second real run is idempotent (sha256 identical, no duplicate entries)
- **(h)** `validate.md` appears in dry-run (existing command glob carries the new command)
