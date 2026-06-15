# Dangerous-command policy lives in an exit-2 hook, not `settings.deny`

**Status:** Extends ADR-0009 (the `security_guard` hook); informs the Unattended-Autonomy PRD.

## Context

ADR-0009 added a `PreToolUse` `security_guard.py` hook that denies real `.env` access and
recursive deletes. The Unattended-Autonomy work now (a) adds network-exfil patterns
(`curl … | sh`, `wget … | bash`, bare `… | sh`) to that same hook, and (b) fills a real
`permissions.allow` list at user scope so N parallel worktree agents stop stalling on
per-tool-use prompts. (a) and (b) collide on one question: where does dangerous-command
policy belong, and is the hook strong enough to hold it once a broad allowlist exists?

## Decision

Keep all dangerous-command denial in the **one hook** (`security_guard.py`), not split into
`settings.deny` — **and make the hook's deny path `exit(2)` (reason to stderr), not the
`exit(0)` + stdout-JSON `permissionDecision: "deny"` it used before.**

## Why exit(2) is required, not optional

Claude Code evaluates permission rules in the order **deny → ask → allow**, first match wins.
A `PreToolUse` hook's JSON `permissionDecision: "deny"` returned with `exit(0)` is a
*suggestion* inside that flow: when a command also matches an `allow` rule, the `allow` wins
and the hook's deny is **silently ignored**. Only a hook that `exit(2)`s stops the call
*before* rules are evaluated, so it overrides even a matching `allow`.

With the old empty allowlist this never bit — nothing dangerous was allow-listed, so the
exit(0) JSON deny had no `allow` to lose to. But this PRD fills the allowlist and explicitly
anticipates it *growing* (graduation; the later `fewer-permission-prompts` flow). The moment
any allow pattern broadens enough to cover a dangerous command, an exit(0) hook's deny goes
silently dead — exactly the silent-failure class this work exists to kill. `exit(2)` makes
the hook a true deny-first barrier that allowlist growth can never undercut.

## Why the hook and not `settings.deny`

`settings.deny` *is* a deny-first, allow-overriding mechanism, so it was the obvious
alternative. Rejected so dangerous-command logic has **one home**: the patterns, the reasons,
and the fail-open-on-parse-error behavior already live in `security_guard.py` with tests;
splitting some denials into `settings.deny` and others into the hook would scatter the policy
across two mechanisms with different match semantics. With `exit(2)`, the hook reaches
deny-first strength, so the single-home consolidation costs nothing in enforcement power.

## Consequences

- `security_guard.py`'s deny path changes for *all* cases (`.env`, recursive delete, exfil),
  not just the new ones — verify the existing two behave identically under `exit(2)`.
- Tests assert **exit code 2 with the reason on stderr**, not a stdout-JSON shape; benign
  near-misses (e.g. `curl -o file url`) must assert `exit(0)` so no false positive
  re-introduces approval friction.
- A future reader tempted to "simplify" by moving exfil into `settings.deny`, or to revert the
  hook to stdout-JSON/exit(0), should read this first: that reopens the silent-override hole.
