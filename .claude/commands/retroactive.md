---
description: Improve the Harness after a bug or miss, so the same class of problem can't recur
argument-hint: <what went wrong | path to the bug/report>
---

# Retroactive

**Input**: $ARGUMENTS

This is the **System Evolution** outer loop (see
[`../skills/system-evolution/SKILL.md`](../skills/system-evolution/SKILL.md)). Do not stop at
patching the surface code — fix the Harness so the problem can't recur.

You are reached through one of two deterministic entry points (ADR-0010), never from memory: the
Validate step's *problem* branch (`/validate` → here), or a session that just fixed a bug already
in the codebase routing here on its way out. Reaching this command is the *trigger* — it surfaces
the option. Whether a full retroactive is warranted is still judgment (severity × recurrence): a
one-off typo doesn't earn one; a recurring class or a defect that reached the codebase silently
does.

Frame the session this way:

> "You let this problem reach the codebase. Look at your Harness — the rules, commands,
> skills, checks, and workflow — and find what we can change so this class of problem can't
> happen again."

---

## Phase 1 — Diagnose

- What was the actual defect, and what was the *root cause* (not the symptom)?
- At which point in the workflow should it have been caught? Plan, Implement, or Validate?
- Was this a one-off, or a class of problem likely to recur?

## Phase 2 — Locate the gap

**Dimension 0 — Is the defect mechanically checkable?** Ask first: can this be expressed as a
lint rule, type check, test case, or grep assertion that returns green or red? If yes, add the
check to `.claude/validate.sh` or the project test suite so the Stop hook (ADR-0009) catches it
next time — reach for the deterministic gate before a prose rule. The check is primary but not
exclusive: if it catches only *this instance* while the underlying *class* stays judgment-shaped,
keep a prose dimension alongside it. Fall through to the prose dimensions below whenever a defect
— or the residue a check can't express — needs design judgment or a human eye.

Check the four AI Layer prose dimensions, in order:

1. **Commands** — was the procedure missing a step? (e.g. the implement flow never ran a
   check that would have caught this)
2. **On-demand context** — do `examples/` or referenced docs need a new or corrected
   pattern?
3. **Global rules** (`CLAUDE.md`) — is an existing constraint too vague to bind, or is one
   missing entirely?
4. **Plan / PRD templates** — is a structural section missing that would have forced the
   right thinking up front?

## Phase 3 — Propose the fix

State the smallest change to the Harness that prevents the whole class of problem. Prefer
sharpening an existing rule/command over adding new surface area — the AI Layer must stay
lean enough to live in the smart zone. For the *prose* portion of a fix, if two layers could
hold it, pick the earliest one in the workflow (a planning-template fix beats a validation-step
fix); this points the opposite way from Dimension 0's gate-first preference because a prose
reminder degrades over distance while a deterministic check does not — so prose belongs earliest
and a check sits fine at the latest layer, the gate.

## Phase 4 — Apply and record

- Make the edit to the relevant Harness file(s) — a check in `.claude/validate.sh` / the test
  suite, or an AI Layer rule/command/skill/example.
- Add a concrete entry to `CLAUDE.md`'s "Do-not" / project-specifics list if a footgun
  was involved.
- Because the Harness is in source control, commit it as its own change with a message
  explaining the originating bug — this is a compounding safeguard for everyone who uses
  the layer next.

## Output

Report: the root cause, which check and/or dimension(s) you changed, the exact edits made, and a
one-line statement of the class of problem now prevented.
