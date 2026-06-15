# Graduation state lives in the live dial; `sync.sh` must not regress it

**Status:** Extends ADR-0003 (global sync) and ADR-0007 (sync mechanics); informs the
Unattended-Autonomy PRD. **Contingent on the graduation probe** (PRD Testing Decisions, third
go/no-go): this ADR's "graduation = `git push` in live `allow`" model holds only if `auto` mode
either drops a `Bash(git push *)` allow rule or still runs the classifier when it is present. If
the probe shows a kept `allow` rule *bypasses* the classifier (leaving force/main push unguarded
after graduation), this ADR is **superseded** by a graduate-by-removal model (delete the live
`ask` entry so push falls to the classifier; graduation marker is not an allow/ask/deny entry).

## Context

The Unattended-Autonomy PRD keeps `git push` on `ask` as the single human checkpoint, and
calls *graduating* it to `allow` "the whole point" — the one global dial that converts
supervised autonomy into unattended autonomy. Graduation is specified as a deliberate one-line
edit to the **live** `~/.claude/settings.json`.

Separately, `sync.sh` additively merges `.claude/settings.shared.json` into that same live
file, and the shared file declares `permissions.ask: ["Bash(git push *)"]` — the
*pre-graduation* posture, by design, so a fresh machine syncs into the safe default. The merge
rule is a uniform union over `allow`/`ask`.

These collide on one key. After the operator graduates (`git push` moved from live `ask` to
live `allow`), the next `sync.sh` run sees the shared file still declaring `git push` under
`ask`, and a blind union re-adds it. Claude Code evaluates `ask` before `allow`, so the
re-added `ask` wins — and the operator is **silently un-graduated** on every sync. The dial
the PRD calls a deliberate one-time flip behaves instead like a spring that snaps back.

## Decision

Graduation state **lives in the live dial**, and `sync.sh` is **graduation-aware**: if
`Bash(git push *)` is already in the live `permissions.allow`, the merge does **not** re-add it
to `ask` from the shared file. This is the one place the otherwise-uniform union yields to a
live-state fact.

## Why here, and not the alternatives

- **Graduate by editing the shared file + re-syncing** — rejected. It makes graduation a
  version-controlled, auditable commit, which is appealing, but the shared file syncs to *every*
  project's user scope, so flipping it there makes a per-operator trust decision a global commit,
  and turns "flip one live line" into "edit a repo asset and run sync." The PRD deliberately
  defines graduation as a live, local dial; its state belongs where the dial is.
- **Drop `git push: ask` from the shared file (initialize once, never reassert)** — rejected. It
  breaks idempotency and fresh-machine reproducibility: a new machine would sync without the
  `ask` checkpoint, losing the safe default the shared file exists to carry.
- **Blind union (status quo before this ADR)** — rejected: the silent un-graduation above.

## Consequences

- `sync.sh`'s merge gains a single `git push`–specific conditional, breaking the "union treats
  every key alike" simplicity for exactly one entry. The trade is deliberate: graduation is the
  PRD's stated payoff and is worth the special case.
- `sync.test.sh` asserts the surviving-graduation case: against a live file that already has
  `Bash(git push *)` in `allow`, sync must not re-add it to `ask`.
- A future reader tempted to "simplify" the merge back to a uniform union should read this
  first: it silently reverts the operator's graduation on the next sync.
- The asymmetry is intentional and narrow — only `git push` (the boundary dial) is exempt.
  Other shared `ask`/`allow` entries are still blindly unioned; they carry no live-state meaning
  that a sync would wrongly overwrite.
