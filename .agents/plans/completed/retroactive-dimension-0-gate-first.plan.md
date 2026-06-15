# Plan: Retroactive Dimension 0 (checkable-before-prose) + gate-first reorder

## Summary
The System Evolution outer loop (`/retroactive` + the `system-evolution` skill) can turn a
bug into a CLAUDE.md rule, a command edit, a context update, or a plan-template change — but
it has **no path that strengthens the deterministic verification gate** (`.claude/validate.sh`,
enforced by the `validate_gate` Stop hook per ADR-0009). For any mechanically-checkable defect
the gate is strictly the better home than a prose rule, yet `retroactive` never sends defects
there. This plan adds that path via three coupled prose edits: (1) a new yes/no **Dimension 0**
in `retroactive.md` Phase 2 that asks "is this defect mechanically checkable?" and routes a yes
to the gate; (2) a scoping amendment to `retroactive.md` Phase 3 so its existing "earliest layer
wins" rule applies *only* to prose fixes (otherwise the file contradicts itself); and (3) a
reorder of `system-evolution/SKILL.md` so "strengthen the verification gate" is the first lever
considered and prose rules are explicitly demoted to the fallback for judgment-shaped defects.
These are prose artifacts — validate structurally (the claims exist, the file is internally
consistent), not behaviorally.

## User Story
As the operator, I want `/retroactive` to first ask "is this defect mechanically checkable?"
and, if yes, add a check to `.claude/validate.sh` or the project test suite (treating prose
rules as the last resort), so that the deterministic gate catches the whole class next time
instead of relying on the agent reading and obeying a hopeful reminder.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | LOW |
| Systems affected | `.claude/commands/retroactive.md`, `.claude/skills/system-evolution/SKILL.md` |
| Issue | #29 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| Both target files exist and have the structure the edits target (retroactive.md Phase 2 "Locate the gap" with a 4-item numbered list; Phase 3 with an "earliest one in the workflow" rule; SKILL.md "The retroactive session" with a 4-dimension list "earliest-in-the-workflow first") | VERIFIED | Read both files this session — `retroactive.md:35-53` has Phase 2 (numbered 1–4) and Phase 3 ("pick the earliest one in the workflow"); `system-evolution/SKILL.md:31-36` has "Then check four dimensions, earliest-in-the-workflow first:" with the same 4-item list. |
| ADR-0009 is the correct citation for the Stop-hook-enforced gate, and the hook/script names are accurate | VERIFIED | `docs/adr/0009-enforce-validate-gate-by-hook-and-split-validate-step.md` exists; CLAUDE.md states "the global `validate_gate` `Stop` hook runs [`.claude/validate.sh`] automatically on session end (fails open when absent)." The PRD (`unattended-autonomy.prd.md`) cites ADR-0009 for the same Stop-hook gate. |
| This is a prose-only change with no behavioral runtime to test; validation is structural (grep for required phrases + human read for internal consistency) | VERIFIED | Both files are markdown command/skill prose, no code. Issue body and PRD both state "These are prose artifacts — validate structurally, not behaviorally." |
| Wording must pass a human review (HITL) before merge | ASSUMED (by design) | Acceptance criterion in the issue: "Wording reviewed by a human (HITL judgment check) before merge." De-risk: surface the exact diff in the Implement report and stop for human read before merge; do not auto-merge. |

## Patterns to Follow

The existing Phase-2 numbered-dimension list — Dimension 0 must read as a *gate* that precedes
this list, using the same terse imperative voice:
```markdown
## Phase 2 — Locate the gap

Check the four AI Layer dimensions, in order:

1. **Commands** — was the procedure missing a step? (e.g. the implement flow never ran a
   check that would have caught this)
2. **On-demand context** — do `examples/` or referenced docs need a new or corrected
   pattern?
3. **Global rules** (`CLAUDE.md`) — is an existing constraint too vague to bind, or is one
   missing entirely?
4. **Plan / PRD templates** — is a structural section missing that would have forced the
   right thinking up front?
// SOURCE: .claude/commands/retroactive.md:35-46
```

The existing Phase-3 prose, whose "earliest one in the workflow" sentence must be scoped to
prose fixes:
```markdown
## Phase 3 — Propose the fix

State the smallest change to the AI Layer that prevents the whole class of problem. Prefer
sharpening an existing rule/command over adding new surface area — the AI Layer must stay
lean enough to live in the smart zone. If two layers could hold the fix, pick the earliest
one in the workflow (a planning-template fix beats a validation-step fix).
// SOURCE: .claude/commands/retroactive.md:48-53
```

The existing skill four-dimension list, whose ordering/framing must be reworked so the gate
leads and prose is the fallback:
```markdown
Then check four dimensions, earliest-in-the-workflow first:

1. **Commands** — is the procedure missing a step?
2. **On-demand context** — do `examples/` or referenced docs need updating?
3. **Global rules** (CLAUDE.md) — is a constraint too vague, or missing?
4. **Plan / PRD templates** — is a structural section absent?
// SOURCE: .claude/skills/system-evolution/SKILL.md:31-36
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/commands/retroactive.md` | UPDATE | Add Dimension 0 gate to Phase 2; scope Phase 3's earliest-layer rule to prose fixes only |
| `.claude/skills/system-evolution/SKILL.md` | UPDATE | Reorder framing so "strengthen the verification gate" leads; demote prose rules to fallback |

## Tasks
Ordered, atomic, each independently verifiable. Tasks 1 and 2 edit the same file (`retroactive.md`)
and together keep it internally consistent — do both before validating that file.

### Task 1: Insert Dimension 0 gate into `retroactive.md` Phase 2
- File: `.claude/commands/retroactive.md`
- Action: UPDATE
- Implement: In Phase 2 ("Locate the gap"), before the existing "Check the four AI Layer
  dimensions, in order:" list, insert a **Dimension 0** presented as a *yes/no gate* (not a
  priority rank). It must ask: *Is the defect mechanically checkable (a lint rule, type check,
  test case, or grep assertion)? If yes → add the check to the project's `.claude/validate.sh`
  or its test suite so the Stop hook (ADR-0009) catches the class next time — a deterministic
  check always beats a prose rule.* Make explicit that only a "no" (the defect needs design
  judgment / a human eye and can't become a green/red check) falls through to the four
  dimensions below. Match the file's terse imperative voice.
- Mirror: `.claude/commands/retroactive.md:35-46`
- Validate: `grep -in "Dimension 0" .claude/commands/retroactive.md` returns a hit; the
  inserted text names "mechanically checkable", "validate.sh", and "ADR-0009"; read Phase 2
  to confirm Dimension 0 reads as a gate that precedes (not a 5th item within) the numbered list.

### Task 2: Scope `retroactive.md` Phase 3 earliest-layer rule to prose fixes
- File: `.claude/commands/retroactive.md`
- Action: UPDATE
- Implement: Amend Phase 3 so the existing "pick the earliest one in the workflow" sentence is
  explicitly scoped to *prose* fixes — i.e. Dimension 0 decides checkable-vs-prose first, and the
  earliest-layer ordering applies only once the fix has fallen through to a prose rule. The two
  rules must not read as contradictory instructions after this edit.
- Mirror: `.claude/commands/retroactive.md:48-53`
- Validate: read Phase 3 — the earliest-layer sentence now references the gate/prose distinction
  (e.g. "once the fix is a prose rule" / "for prose fixes"); Phase 2's gate-first rule and Phase
  3's ordering rule are mutually consistent.

### Task 3: Reorder `system-evolution/SKILL.md` to gate-first, prose-last
- File: `.claude/skills/system-evolution/SKILL.md`
- Action: UPDATE
- Implement: In "The retroactive session" section, rework the framing so "strengthen the
  verification gate" (add a deterministic check to `.claude/validate.sh` / the test suite for a
  mechanically-checkable defect) is the **first** lever considered, and prose rules (CLAUDE.md
  do-not entries) are explicitly demoted to the **fallback** for judgment-shaped defects that
  can't become a green/red check. Keep the section lean (skill stays in the smart zone); cite
  ADR-0009 for the Stop-hook gate, consistent with `retroactive.md`. Preserve the existing
  `→ run /retroactive to drive this.` pointer and the four prose dimensions (now framed as the
  prose fallback, no longer the primary list).
- Mirror: `.claude/skills/system-evolution/SKILL.md:31-36`
- Validate: `grep -in "validate.sh\|verification gate\|ADR-0009" .claude/skills/system-evolution/SKILL.md`
  returns hits; read the section to confirm the gate leads and prose is named as the fallback.

## Validation
This is a prose change; there are no project lint/type/test commands that cover markdown content.
Validation is structural + human.

- **Structural (greppable acceptance):**
  - `grep -in "Dimension 0" .claude/commands/retroactive.md` → hit (AC-1)
  - `grep -in "mechanically checkable\|validate.sh" .claude/commands/retroactive.md` → hit (AC-1)
  - Phase 3 earliest-layer sentence scoped to prose (read; AC-2)
  - `grep -in "validate.sh\|verification gate" .claude/skills/system-evolution/SKILL.md` → hit (AC-3)
  - Gate-first / prose-last ordering present in **both** files (read both; AC-3)
- **Internal consistency:** read `retroactive.md` end-to-end — Phase 2 Dimension 0 (gate-first)
  and Phase 3 (earliest-layer scoped to prose) must not contradict each other (AC-2).
- **Project gate:** run `.claude/validate.sh` if present (fails open when absent per CLAUDE.md) —
  expect it not to regress.
- **HITL:** surface the full diff in the Implement report and stop for a human wording review
  before merge (AC-4). Do not auto-merge.

## Acceptance Criteria
- [ ] Dimension 0 exists in `retroactive.md` Phase 2 as a checkable-vs-prose gate (not a 5th priority rank).
- [ ] Phase 3's earliest-layer rule is explicitly scoped to prose fixes (file is not self-contradictory).
- [ ] The gate-first / prose-last ordering is present in **both** `retroactive.md` and `system-evolution/SKILL.md`.
- [ ] Every external-behavior claim is VERIFIED by a probe, or carried as an explicit risk (see Assumptions & Risks — all VERIFIED except the HITL gate, which is by-design).
- [ ] Wording reviewed by a human (HITL judgment check) before merge.
- [ ] Follows existing terse imperative prose style of both files.
