# Implement Report: retroactive-dimension-0-gate-first

## Summary

Three prose edits across two files add a "Dimension 0" gate to the retroactive workflow so
mechanically-checkable defects are routed to the deterministic verification gate
(`.claude/validate.sh` / Stop hook, ADR-0009) before prose rules are even considered.

## Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Insert Dimension 0 gate into `retroactive.md` Phase 2 | ✅ | Inserted as a yes/no gate paragraph before the numbered list; references `validate.sh` and ADR-0009 |
| 2 | Scope Phase 3's earliest-layer rule to prose fixes | ✅ | Added "For prose fixes (Dimension 0 said no)," qualifier; no contradiction with Phase 2 |
| 3 | Reorder `system-evolution/SKILL.md` to gate-first, prose-last | ✅ | Gate paragraph leads; prose dimensions now framed as fallback; `/retroactive` pointer preserved |

## Validation Results

All structural grep acceptance criteria passed:

```
grep -in "Dimension 0" .claude/commands/retroactive.md         → 2 hits (Phase 2 gate + Phase 3 scope)
grep -in "mechanically checkable|validate.sh|ADR-0009" ...     → 3 hits in retroactive.md
grep -in "validate.sh|ADR-0009" system-evolution/SKILL.md      → 2 hits
```

`.claude/validate.sh` → `PIV checks passed.` (no regression)

## Files Changed

- `.claude/commands/retroactive.md` — +13 / -2 lines
- `.claude/skills/system-evolution/SKILL.md` — +7 / -2 lines

## Deviations from Plan

None. All three tasks implemented exactly as specified. The `retroactive.md` Phase 3 wording
chose "For prose fixes (Dimension 0 said no)," as the scope qualifier — slightly more
self-contained than the plan's examples ("once the fix is a prose rule") but equivalent and
consistent with the file's voice.

## Tests Written

None applicable — prose-only change. Structural grep assertions serve as the verification
layer per the plan's validation strategy.

## HITL Gate

Per acceptance criterion AC-4: **do not merge until a human has reviewed the wording diff.**
The branch is `feat/29-retroactive-dimension-0-gate-first`. Next step: `/validate` in a fresh
session, then open a PR for human wording review before merge.
