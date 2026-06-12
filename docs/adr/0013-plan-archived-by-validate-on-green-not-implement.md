# Plan archived by Validate on a green gate, not by Implement

The PIV plan file stays in `.agents/plans/` through Implement and is archived to
`.agents/plans/completed/` by `/validate` when the gate passes — not by `/implement` at the
end of implementation, and not post-merge. "Completed" therefore means *passed validation*,
not *implementation done* or *merged*. `/validate`'s blank-input resolution also falls back to
`completed/` so a re-validation after a prior pass stays idempotent.

## Why

Implement archiving the plan (the earlier behavior) moved it out of where `/validate`'s
blank-input resolution looks (`.agents/plans/{slug}.plan.md`), so Validate silently fell to
"no plan — E2E skipped." Two alternatives were rejected:

- **Implement archives at Phase 4 end.** The producer archiving its own plan reads naturally,
  but it hides the plan from the very next step that needs it, and labels a plan "completed"
  before it has passed any gate.
- **Archive post-merge.** Semantically purest ("completed" = merged), but the merge is a human
  action outside any agent session — there is no command home for the move, so relying on it
  means trusting the agent to "remember" to come back, the failure mode hooks and deterministic
  handoffs exist to prevent.

Validate-on-green is the last point the plan is needed (Phase 3 has just re-read its E2E
section) and the last deterministic agent touchpoint, so it owns the move.
