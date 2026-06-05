# The PM role is a main-session persona skill, not a sub-agent

ADR-0001 keeps the PM role for a solo developer but left the **mechanism** open. The build
handoff proposed authoring it from `agency-agents/product/product-manager.md` as a Claude
Code **sub-agent**. This ADR rejects that mechanism.

**Decision:** the PM role is played by the **main session adopting a lean PM persona**,
packaged as the `strategic-planning` skill — not as a Claude Code sub-agent. No
`.claude/agents/` PM definition is created.

Two reasons:

1. **Mechanism.** A Claude Code sub-agent runs in a separate context and returns only a
   final summary; it cannot hold a multi-turn, interactive brain dump → clarifying-questions
   dialogue with the developer. The PM role *is* exactly that dialogue. This is the same
   interaction-shape test as ADR-0005: an interactive session is a skill, not a sub-agent.

2. **Source fit.** `agency-agents/product/product-manager.md` is a ~470-line enterprise-org
   PM persona (go-to-market briefs, sprint-health snapshots, RICE scoring, NPS, roadmap
   Now/Next/Later). Roughly nine-tenths of it is irrelevant to a solo developer with a
   non-technical supervisor and no marketing / sales / launch function. Only its **judgment
   instincts** are mined — lead with the problem not the solution, ask "why" repeatedly, name
   Non-Goals, say no, hold scope discipline — and the organisational machinery is dropped.

The persona is **not redundant** with the upstream `to-prd` skill: `to-prd` is a mechanical
PRD generator with generic clarifying questions; the PM persona is the judgment layer that
sharpens those questions and stands in for the absent human PM (ADR-0001). The skill
orchestrates brain dump → clarifying questions → `to-prd` → `to-tickets` in the main session.

Field evidence agrees: `ai-transformation-workshop` ships **no** PM sub-agent (only
`create-prd` / `create-stories` commands), and the knowledge base records the PM role as
"absorbed into the coding agent," never a standalone agent.

Alternatives rejected:
- **PM as a Claude Code sub-agent** (the handoff's proposal): the mechanism cannot conduct
  the interactive dialogue; it could only draft a PRD from a pasted transcript, losing the
  clarifying-questions value that is the whole point of the role.
- **Adopt `agency-agents/product-manager.md` wholesale**: imports enterprise
  GTM/sprint/roadmap baggage with no fit for this context.

Consequence: block 2 of the Phase 1 build is a `strategic-planning` persona skill, not an
agent file.
