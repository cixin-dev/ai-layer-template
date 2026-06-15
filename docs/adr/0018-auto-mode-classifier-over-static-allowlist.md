# `auto` mode (classifier) for the sandbox posture, not `acceptEdits` + a static allowlist

**Status:** Informs the Unattended-Autonomy PRD; relates to ADR-0016 (deny hook) and ADR-0017
(graduation dial).

## Context

The Unattended-Autonomy PRD removes per-tool-use approval friction so N parallel worktree agents
stop stalling on a human click. The original design did this with `permissions.defaultMode:
"acceptEdits"` plus a hand-filled `permissions.allow` list enumerating the dev/test/git toolchain
(`npm`, `pytest`, `uv`, `git add/commit/...`).

Mid-design, a doc-confirmed Claude Code feature surfaced: **`auto` mode** (v2.1.83+). It delegates
each tool call to a separate *safety-classifier model* that runs normal operations without
prompting and interrupts only on actions that escalate beyond the request, target unrecognized
infrastructure, or look driven by hostile content. `acceptEdits`, by contrast, covers only file
edits and common filesystem commands — **not** Bash execution — so under it the toolchain must be
enumerated by hand.

## Decision

Adopt **`defaultMode: auto`** as the sandbox posture. Ship **no** hand-filled toolchain allowlist.
Keep the deterministic safety floor only where determinism actually matters — `validate.sh` (the
gate, ADR-0009) and `security_guard.py` (the deny hook, ADR-0016) — both retained unchanged in
spirit.

## Why this over the static allowlist

- **No enumeration treadmill.** `acceptEdits` doesn't cover Bash, so every test runner, flag, or
  new tool would re-introduce a prompt — the exact friction `fewer-permission-prompts` automates
  chasing. The classifier generalizes by *intent*, so the list disappears and new tools don't
  regress.
- **Intent-awareness the allowlist can't have.** A static `allow` pattern cannot tell a benign
  command from a prompt-injection-driven one that happens to match it. The classifier reads intent
  and hostile-content signals, so `auto` is *safer*, not just less work — including in the
  "posture without container" zone (user-scope mode applied where no worktree and no validate gate
  exist), which is the PRD's accepted residual risk.
- **Consistent with the PRD's own thesis.** The thesis is "verify outputs, not inputs — let the
  sandbox run free, gate the boundary." `auto` *is* "run free with a light intent check"; the real
  gate stays at the boundary.

## The tension, and why it's acceptable

Thesis B of the same PRD prizes **deterministic** checks over **probabilistic** ones (a
`validate.sh` check beats a hopeful prose rule). `auto`'s classifier is a probabilistic model — at
first glance a contradiction. It is reconciled by *layer*: the classifier governs the **input**
permission layer, which the PRD explicitly says we should *not* lean on for safety; the
**deterministic** layer is kept exactly where the thesis demands it — at the boundary
(`validate.sh`) and for known-dangerous classes (`security_guard.py` `exit(2)`, which fires in any
mode and cannot be talked around). We accept a probabilistic *inner* layer precisely because the
*outer* floor is deterministic.

## Consequences

- `settings.shared.json` carries `defaultMode: auto` and **no** `permissions.allow` toolchain
  entries; the `allow` union in `sync.sh` becomes preserve-only.
- A new go/no-go probe: `auto` needs v2.1.83+. If the installed Claude Code is older, fall back to
  the original `acceptEdits` + allowlist design rather than ship a mode the harness rejects.
- New, narrower residual risk: the classifier can misjudge, and it only falls back to prompting
  after 3 consecutive / 20 total blocks per session. Held by the same deterministic floor
  (`git push: ask`, `security_guard.py`, `validate.sh`).
- A future reader who sees `defaultMode: auto` with a near-empty allowlist and is tempted to
  "harden" it by enumerating safe commands should read this first: the empty allowlist is the
  decision, not an omission.
