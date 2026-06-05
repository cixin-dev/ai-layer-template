---
description: Improve the AI Layer after a bug or miss, so the same class of problem can't recur
argument-hint: <what went wrong | path to the bug/report>
---

# Retroactive

**Input**: $ARGUMENTS

This is the **System Evolution** outer loop (see
[`../skills/system-evolution/SKILL.md`](../skills/system-evolution/SKILL.md)). The PIV Loop just
surfaced a problem. Do not stop at patching the surface code — fix the AI Layer so the
problem can't recur.

Frame the session this way:

> "You let this problem reach the codebase. Look at your AI Layer — the rules, commands,
> skills, and workflow — and find what we can change so this class of problem can't happen
> again."

---

## Phase 1 — Diagnose

- What was the actual defect, and what was the *root cause* (not the symptom)?
- At which point in the workflow should it have been caught? Plan, Implement, or Validate?
- Was this a one-off, or a class of problem likely to recur?

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

## Phase 3 — Propose the fix

State the smallest change to the AI Layer that prevents the whole class of problem. Prefer
sharpening an existing rule/command over adding new surface area — the AI Layer must stay
lean enough to live in the smart zone. If two layers could hold the fix, pick the earliest
one in the workflow (a planning-template fix beats a validation-step fix).

## Phase 4 — Apply and record

- Make the edit to the relevant AI Layer file(s).
- Add a concrete entry to `CLAUDE.md`'s "Do-not" / project-specifics list if a footgun
  was involved.
- Because the AI Layer is in source control, commit it as its own change with a message
  explaining the originating bug — this is a compounding safeguard for everyone who uses
  the layer next.

## Output

Report: the root cause, which dimension(s) you changed, the exact edits made, and a
one-line statement of the class of problem now prevented.
