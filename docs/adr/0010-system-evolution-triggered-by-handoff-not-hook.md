# System Evolution is triggered by workflow handoff, not a lifecycle hook

**Context.** This repo enforces mechanical floors with hooks (the validate gate, the
security guard — see ADR-0009). The obvious next step is to trigger the System Evolution
outer loop the same way — e.g. a `SessionEnd` hook prompting "run `/retroactive`?" — so the
loop stops depending on the agent remembering the command exists.

**Decision.** We don't trigger it with a hook. System Evolution is triggered *through the
workflow*: PIV's Validate step hands a *problem* off to `/retroactive`, and any session that
fixes a bug already in the codebase ends by routing there too. That trigger only *surfaces
the option*; the judgment of whether to actually run a retroactive (severity × recurrence)
stays a separate layer, as `system-evolution/SKILL.md` already says.

**Why.** A hook fires on mechanical lifecycle events; "did a defect of some class escape to
the codebase?" is a semantic judgment a hook can't make. `SessionEnd` specifically is
teardown — non-interactive, it can't conduct a "want to run?" exchange. The general rule
this draws: **hooks enforce objective red/green floors; handoffs carry semantic flow.**
This bounds what the hooks adopted in ADR-0009 are *for*.

**Rejected.**
- `SessionEnd` / lifecycle hook as the trigger — can't judge the semantic condition, and
  `SessionEnd` is non-interactive teardown.
- Unconditional `SessionStart` nudge every session — alarm fatigue defeats the purpose and
  fires in planning/research sessions where "did a bug escape?" is meaningless.
- Auto-running `/retroactive` on every bug — collapses the trigger/decision split and bloats
  the AI Layer against the smart-zone constraint (`system-evolution/SKILL.md`: "not every bug
  warrants a retroactive session").
