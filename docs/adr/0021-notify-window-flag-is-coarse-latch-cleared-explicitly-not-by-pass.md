# The validate-notify tmux window flag is a coarse, per-project latch cleared only by an explicit `clear` — never by `pass`

**Status:** Accepted (2026-06-16); relates to Issue #40 (Channel A notification), the
`validate gate` / `/validate` split (ADR-0009), and the read-only `dashboard` command. Born
from the `notify-validate-events` plan grilling, which overturned the plan's first-draft
"`pass` clears the flag" once the operator's real tmux layout was pinned down.

## Context

`notify.sh` flags the operator's tmux **window** on a validate verdict by setting a sticky
`window-status-style` (red) plus a `@claude_attention` option. The plan's first draft assumed
one work-stream per window, so it modeled clearing as "a `pass` resets the window."

The operator's actual layout (memory `remote-ssh-tmux-workflow`): **one tmux window per
project**, and inside that window **multiple split panes running several PIV flows
concurrently**, often with one pane as a live dashboard. tmux gives a status-bar entry to
**windows, not panes**, so the only "scan from anywhere, which one needs me" signal is
window-granular — i.e. **per project**, aggregating N concurrent streams into a single colour
slot.

That aggregation breaks "`pass` clears": pane 1 fails (window → red), pane 2 passes (`pass` →
clear), and the still-unresolved fail in pane 1 is **silently wiped**. A single colour slot
cannot represent "one stream failed, another passed." The dangerous direction is a
**false-clear** (red wiped while a fail is live → operator stops looking → miss), far worse than
a **stale-red** (resolved but still red → merely annoying). For a notification whose whole point
is *stop polling the dashboard*, the rule must never false-clear.

The obvious auto-clear candidate — the `dashboard` command, which already shows per-worktree
validate verdicts — is contractually **read-only / no side effects**, so it cannot be the thing
that mutates the tmux flag without breaking its own invariant (and would be out of #40's scope).

## Decision

Treat the window flag as a **coarse, per-project latch** with an explicit release, and let the
**network push** (ntfy) be the reliable AFK channel rather than the window colour.

- **`fail`** → set red (latch) + bell + push. Severity floor: a red is never downgraded.
- **`info`** (permission/idle hooks) → set yellow **only if the window is not already red** +
  bell. **No push** — these are at-keyboard, real-time "which window is blocked" signals, and
  `idle_prompt` is too frequent to put on the phone.
- **`pass`** → push + bell, and **does not touch the window colour** (avoids the cross-stream
  false-clear).
- **`clear`** → the *only* thing that resets the window (`@claude_attention` + `window-status-style`).
  Operator-triggered (run it, or bind it locally / call it from their own dashboard-refresh loop —
  all outside the synced machinery, because only the operator knows when the *whole project* is
  dealt with).

Severity precedence on the single slot is `fail > info > pass`, with `pass` removed from the
colour path entirely. Network push is reserved for the two PIV **milestones** (`fail`, `pass`).

This composes with the existing **FAIL-via-hook / PASS-via-command asymmetry** (`validate_gate.py`
fires `fail` deterministically in any session; `/validate` Phase 5 fires `pass` only in a real
validate session): the deterministic channel latches the flag, the deliberate channel only
nudges the phone.

## Why this over the alternatives

- **`pass` clears the window (plan's first draft)** — rejected: under one-window-per-project with
  concurrent panes, a peer pass false-clears a live fail. Safe only in the one-stream-per-window
  world that does not hold here.
- **Per-pane fail-set keyed on `$TMUX_PANE`** (window red iff any pane in its set is failing) —
  rejected for #40: precise auto-clear, but adds shell-side set state and leaks **stale pane ids**
  when a pane is killed mid-fail. The colour does not need to be a faithful aggregate once the
  dashboard owns per-stream truth and the push owns reliability.
- **Auto-clear from the dashboard on all-green** — rejected: violates the dashboard's read-only /
  no-side-effects contract, and is out of #40 scope.
- **Set-only, no clear at all (the issue as written)** — rejected: a latch with no release paints
  every project window red within a day and the signal dies. The `clear` verb is the minimum that
  makes the latch usable.

## Consequences

- The window colour is a **glanceable hint, not a source of truth**. Truth comes from the
  **network push** (never missed, AFK) and the **dashboard pane** (per-stream detail). A future
  reader who sees `pass` *not* clearing the flag, or wants the dashboard to auto-clear it, should
  read this ADR first — both are deliberate.
- `notify.sh`'s level argument carries a fourth value, `clear`, beyond the `pass`/`fail`/`info`
  in the issue signature; `info` and `clear` never hit the network sink.
- "The flag targets the *correct* project window" is **verified**, not assumed: the Stop-hook
  subprocess inherits `TMUX_PANE`, so `tmux display-message -p '#{window_id}'` resolves to the
  failing agent's own pane's window, and `set-option -w -t <win>` colours that window regardless
  of which window is currently active.
- **Stale-red is accepted**: a project window can stay red after the work is resolved until the
  operator runs `clear`. This is the deliberate safe bias (annoying over miss).
- **Open follow-ups** (out of #40): per-stream pane-border colouring for in-window detail;
  marker-file dedup if repeated FAIL pushes in one looping session prove noisy; an automatic
  `clear` trigger that does not violate the dashboard's read-only contract (e.g. `/clean-worktree`).
