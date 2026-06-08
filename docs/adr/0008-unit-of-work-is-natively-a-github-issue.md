# The unit of work is natively a GitHub Issue

**Status:** Supersedes ADR-0004.

ADR-0004 forked upstream `to-issues` into a local `to-tickets` skill on the premise that
`to-issues`' output — "issue / story / Jira" — pollutes this project's `CONTEXT.md` glossary,
so the unit of work was named **Ticket** and written to local `.agents/tickets/{NN}-{slug}.md`
files instead of a tracker. The `_Avoid_` line that justified the name read "issue (binds to a
specific tracker)" — i.e. the whole point of "Ticket" was tracker-independence.

**Decision:** the unit of work is natively a **GitHub Issue**, and is named **Issue**. The
implementer agent's intake source — in this solo + agentic workflow — is a GitHub Issue, a
specific tracker. Naming the unit "Ticket" to stay tracker-independent was over-engineering:
this project will not swap trackers, and a tracker-independent local file that must then be
mirrored into GitHub is an air-gap with no payoff. Ubiquitous Language requires one name that
survives the local→GitHub boundary; "Ticket → Issue" at that boundary is exactly the one-thing-
two-names this project forbids. So the name follows the concept (an Issue), not the storage
location.

This **retires the `to-tickets` fork before it was built** — sunk cost is zero, the skill was
only ever a planning Ticket (Ticket 02), now withdrawn. Upstream `to-issues` is **kept**: it is
the eventual producer, not a glossary polluter. "issue" is a platform-fact noun here (like
`commit` or `pull request`), not a forbidden vocabulary word. Accordingly, Ticket 01's
`sync.sh` drops its `to-tickets ⇒ remove to-issues` supersession map: nothing supersedes
`to-issues`.

**Transitional state (this is the surprising part).** This repo is not yet on GitHub. Until the
cutover, an Issue is *drafted* as a local file under `.agents/tickets/` — a crutch, not a second
concept. To avoid churning a scaffold that is about to be replaced, only the **glossary source
of truth** flips now (`CONTEXT.md`, this ADR, Tickets 01–02). The legacy word "Ticket" survives
transitionally in the permanent machinery (`CLAUDE.md`, the PIV skills, `/plan` + `/implement`)
and in the `.agents/tickets/` path. The **GitHub cutover** is the single trigger that completes
the rename: connect GitHub, adopt upstream `to-issues` as the producer, migrate the local drafts
to real Issues, and sweep the residual "Ticket" wording in one pass.

Alternatives rejected:
- **Keep the `to-tickets` fork as a pre-GitHub local generator** — leaves two producers and a
  local→GitHub mirror step (the air-gap) to dismantle later; defers the cost without removing it.
- **Push to GitHub now and skip the crutch** — cleanest end state, but the repo is deliberately
  pre-GitHub for a while longer and planning continues locally via grill in the meantime.
- **Rename "Ticket" everywhere immediately** — full Ubiquitous-Language consistency now, but
  churns permanent machinery and a dying scaffold pre-GitHub, then has to be touched again at the
  cutover. Deferring to one clean sweep is cheaper.

Consequence: a deliberate, documented glossary/machinery mismatch during the transition — the
glossary says **Issue**, parts of the machinery and the `.agents/tickets/` path still say
**Ticket**. This ADR is the record that the mismatch is intentional and time-boxed to the GitHub
cutover, not drift.
