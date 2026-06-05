# Skills for Phase 1, commands for Phase 2 — split by interaction shape, not by source

Two reference implementations of the same agentic workflow disagree on packaging. Cole
Medin's `ai-transformation-workshop` packages project-setup machinery (`create-prd`,
`create-stories`, `plan`, `implement`) as **commands** — its governing rule is "commandify
everything: if you type it more than twice, make it a command." Cole's later
`harness-engineering-demo` drops the `commands/` layer entirely in favour of **skills** with
`disable-model-invocation: true`. The knowledge base records Cole's own rule as deliberately
ambiguous ("prompt something more than three times → make it a command *or* skill"). So
**provenance cannot decide this** — two authorities conflict, and the trajectory looks like
commands → skills.

**Decision:** choose by **interaction shape**, not by source.

- A long, interactive, multi-turn **session** that would misbehave if auto-triggered → **skill**
  (with `disable-model-invocation`).
- A one-shot, `$ARGUMENTS`-driven **procedure** that produces a single file → **command**.

Applied: **Phase 1** (Alignment grilling; Strategic Planning's PRD and ticket dialogue) is
conversational → **skills**. **Phase 2** (`plan` / `implement` / `retroactive` — take a
ticket or plan path, emit a file) is procedural → **commands** (unchanged).

The cross-phase asymmetry is principled, not accidental: Phase 1 is dialogue, Phase 2 is
execution. It also resolves a granularity worry — both Strategic Planning steps (PRD, tickets)
stay skills, so we need neither fork the non-conflicting `to-prd` nor rewrite the existing,
working Phase 2 commands.

Alternatives rejected:
- **Commandify everything** (`ai-transformation-workshop`): forces interactive grilling and
  PRD dialogue into a `$ARGUMENTS` command, fighting its conversational nature.
- **Skills-only** (`harness-engineering-demo`): would require rewriting the existing, working
  Phase 2 commands for no behavioural gain.

Consequence: new Phase 1 machinery is authored or forked as **skills**; Phase 2 stays
**commands**. When a step is an interactive session, prefer a skill.
