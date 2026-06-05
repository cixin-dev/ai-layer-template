---
name: system-evolution
description: The outer loop that turns each bug into a permanent improvement to the AI Layer. Use after a PIV Loop surfaces a defect, when a mistake recurs, or when the user mentions retroactive sessions, improving CLAUDE.md/commands/skills, or stopping a class of problem from recurring.
---

# System Evolution

The outer loop around the [PIV Loop](../piv-loop/SKILL.md). When implementation surfaces a bug or a
miss, the lesson isn't "fix this code" — it's "the AI Layer let this through." The AI Layer
(CLAUDE.md + commands + skills + examples) is a versioned, reviewable, shareable asset.
Improving it is how a one-time mistake becomes a permanent, compounding safeguard.

## Two loops

- **Inner loop** (PIV went fine): finish the ticket → merge → take the next ticket.
- **Outer loop** (PIV surfaced a problem): pause → run a retroactive session → improve the
  AI Layer → return to the next PIV.

## The retroactive session

Frame it bluntly:

> "You let this problem reach the codebase. Look at your AI Layer — rules, commands,
> skills, workflow — and find what we can change so this class of problem can't recur."

Then check four dimensions, earliest-in-the-workflow first:

1. **Commands** — is the procedure missing a step?
2. **On-demand context** — do `examples/` or referenced docs need updating?
3. **Global rules** (CLAUDE.md) — is a constraint too vague, or missing?
4. **Plan / PRD templates** — is a structural section absent?

→ run `/retroactive` to drive this.

## The compounding mechanism

Because the AI Layer lives in source control, each fix is a commit that protects everyone
who uses the layer afterward. A personal post-mortem becomes a team-wide prevention. The
more often you run the outer loop, the more the system compounds.

## Judgment

Not every bug warrants a retroactive session. Weigh severity and recurrence: a one-off typo
doesn't; a pattern the agent keeps repeating, or a defect that reached the codebase
silently, does. Prefer sharpening existing rules over adding new ones — the AI Layer has to
stay lean enough to live in the smart zone.
