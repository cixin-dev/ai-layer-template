# Report: CONTEXT.md glossary slim-down

## Summary
Slimmed the 6 "fat" term entries in `CONTEXT.md` (`validate gate`, `sandbox`, `boundary`,
`opaque code execution`, `dangerous push`, `notification`) back to the lean glossary shape
(def + `_Avoid_` + `(ADR-00XX)` pointer) the front entries already use. Every dropped "why"
sentence was moved into its ADR (verified covered) or retained in a sibling entry — zero loss.
One verified ADR-0020 Consequences bullet was added first so the `dangerous push` lease detail
had a home before being dropped. No code touched, no behavior change.

## Tasks completed
| # | Task | Status |
|---|------|--------|
| 1 | Add verified lease-allowance line to ADR-0020 | ✅ |
| 2 | Slim `validate gate` | ✅ |
| 3 | Slim `sandbox` | ✅ |
| 4 | Slim `boundary` (drop exfiltration sentence — survives in opaque code execution) | ✅ |
| 5 | Slim `opaque code execution` (keep 2 mechanism names + exfiltration clause) | ✅ |
| 6 | Slim `dangerous push` (lease detail dropped → ADR-0020 via Task 1) | ✅ |
| 7 | Slim `notification` (keep two-axis + invariant + full `_Avoid_`) | ✅ |
| 8 | Zero-loss + comprehension re-read | ✅ |
| 9 | Gates + report + PR | ✅ |

## Validation results
- **Local gate** `bash .claude/validate.sh` → `PIV checks passed.` (exit 0).
- **Doc gate dry-run** `bash scripts/doc_change_gate.sh <cf> <pr-body>` → exit 0 (PR body's
  `## 變更說明` + CJK satisfies the CI blocker before push).
- **Zero-loss audit** (Task 8 diff walk) — every removed sentence is quoted-covered in its cited
  ADR or retained in a sibling entry. Two highest-value drops spot-checked directly against the
  ADRs:
  - validate gate sync / opt-in / fails-open → ADR-0009:51,56,62-67 (verbatim).
  - sandbox "posture without container" = accepted residual risk → ADR-0018:36-37,59 (verbatim).
- **Lease line** verified against `.claude/hooks/security_guard.py`: `:130` matches `--force`
  with negative lookahead `(?!-with-lease|-if-includes)` (lease passes); `:136-138` deny
  `main`/`master` destinations (so lease-to-default is still denied — hence "to a non-default
  branch"). Not softened.
- **ADR pointers**: all 6 slimmed entries carry their `(ADR-00XX)` pointer; every bold cross-ref
  term (`**boundary**`, `**worktree**`, `**sandbox**`, `**dangerous push**`,
  `**opaque code execution**`, `**validate gate**`, `` `/validate` ``, `` `dashboard` ``) still
  resolves.

## Files changed
- `CONTEXT.md` — 6 entries slimmed (276 → 245 lines).
- `docs/adr/0020-dangerous-push-floor-in-hook-not-permission-layer.md` — one verified
  lease-allowance Consequences bullet appended after the "Scope of the floor" bullet.

## Tests written
None — documentation-only change. The verification gate for doc edits is the doc_change_gate +
zero-loss diff walk + the validate.sh PIV gate, all run above. No new behavior to cover with a
unit test.

## Deviations from plan
1. **ADR-0020 bullet gained a dated lead-in.** The plan's Task 1 gave the bullet text without a
   date, but the "Mirror" reference (`docs/adr/0020-...md:88`) pointed at the *dated* Consequences
   bullet style ("Scope of the floor (added 2026-06-16, #36 plan grilling)"). To match it, the new
   bullet leads with `**Lease family allowed to non-default branches (added 2026-06-24, glossary
   slim-down):**`. Content is the plan's verbatim verified text, unchanged.
2. **Line reduction 31, not ~50.** Plan estimated `CONTEXT.md` would drop to ~215-225 lines; actual
   is 245 (−31). The plan explicitly framed the goal as the *shape* (def + `_Avoid_` + pointer),
   noting "the disease is comprehension, not line count." All 6 entries match the target shape; the
   estimate was loose, not a missed requirement.

## Out of scope (noted, not done — per plan)
- ADR consolidation (0016/0019/0020), an ADR index, and the lean front entries (lines 1–141):
  untouched.
- The `### Unattended Autonomy` prose block: left as-is (section preamble, not one of the 6 named
  fat entries). Possible follow-up if a future pass wants to slim it.
- ADR-0016's `curl|sh` "network-exfil" mislabel and ADR-0021's stale "Channel A/B" naming:
  pre-existing, deliberately not "fixed" here.

## Next step
`/validate .agents/plans/context-glossary-slim-down.plan.md` in a fresh session, then human review
of the PR.
