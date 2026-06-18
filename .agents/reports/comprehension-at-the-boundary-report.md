# Report: comprehension-at-the-boundary

## Tasks completed

- ✅ **Task 1** — CI comprehension floor (TDD). Created `scripts/doc_change_gate.sh` and `scripts/doc_change_gate.test.sh` (5 cases, all green). Updated `.github/workflows/ci.yml` to run the test suite and add a `pull_request`-only gate step.
- ✅ **Task 2** — `strategic-planning` skill: inline capture now narrates the new term in TC and waits for confirmation; escalation handoff now injects the TC-narration + dedicated-PR contract.
- ✅ **Task 3** — `CLAUDE.md`: added routing Do-not (feature ideas → `strategic-planning`; no cold-start `grill-with-docs`) + TC-comprehension Do-not (canonical docs stay English; TC only in PR body / chat). The pre-existing uncommitted `## Communication` section was included in the same commit per updated plan.
- ✅ **Task 4** — `docs/adr/0022-comprehension-at-the-boundary.md` created.

## Validation results

- `bash scripts/doc_change_gate.test.sh` — **5/5 passed**
- `bash .claude/validate.sh` (full suite including PIV check) — **green after report written**

## Files changed

| File | Action |
|------|--------|
| `scripts/doc_change_gate.sh` | CREATED |
| `scripts/doc_change_gate.test.sh` | CREATED |
| `.github/workflows/ci.yml` | UPDATED — added test line + PR gate step |
| `.claude/skills/strategic-planning/SKILL.md` | UPDATED — inline capture + handoff contract |
| `CLAUDE.md` | UPDATED — Communication section + 2 Do-not entries |
| `docs/adr/0022-comprehension-at-the-boundary.md` | CREATED |

## Deviations from plan

- **CLAUDE.md uncommitted change included**: the pre-existing `## Communication` section (stashed from main) was included in Task 3's commit rather than treated as a separate concern. Plan was updated to reflect this before execution.
- **No deviation in gate logic**: the `grep -P` CJK check and the `^#{1,6}\s*變更說明` header check match the plan spec exactly.

## Tests written

`scripts/doc_change_gate.test.sh` — 5 cases:
1. No canonical changes → pass
2. `CONTEXT.md` + qualified TC body → pass
3. `CONTEXT.md` + empty body → fail
4. `docs/adr/*` + English-only body → fail
5. `docs/adr/*` + qualified TC body → pass
