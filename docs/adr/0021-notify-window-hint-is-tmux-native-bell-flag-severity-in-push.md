# The validate-notify window hint is tmux's native bell flag; severity lives in the network push

**Status:** Accepted (2026-06-16); relates to Issue #40 (Channel A notification), the
`validate gate` / `/validate` split (ADR-0009), and the read-only `dashboard` command. Born
from the `notify-validate-events` plan grilling and **re-cut by a second grilling before it
landed**: the first draft built a custom per-window colour latch released by an explicit
`clear`; the slim design below replaces that whole machinery with tmux's own bell flag.

## Context

`notify.sh` signals the operator on a validate verdict. Two questions decide its shape: *how
does a window-granular hint appear and clear*, and *where does severity live*.

The operator's tmux layout (memory `remote-ssh-tmux-workflow`): **one tmux window per
project**, and inside it **multiple split panes running several PIV flows concurrently**, often
with one pane as a live dashboard. tmux gives a status-bar entry to **windows, not panes**, so
the only "scan from anywhere, which one needs me" signal is window-granular — one colour slot
aggregating N concurrent streams.

That aggregation is the whole problem. A custom per-window colour set on `fail` and released on
`pass` **false-clears**: pane 1 fails (window flagged), pane 2 passes (`pass` → clear), and pane
1's still-unresolved fail is silently wiped. A single slot cannot represent "one stream failed,
another passed." The dangerous direction is the **false-clear** (red wiped while a fail is live
→ operator stops looking → miss), far worse than a **stale flag** (resolved but still flagged →
merely annoying). So a `pass`-clears latch is unsafe; and a set-only latch with *no* release
flags every project window within a day until the signal dies — which is what forced a custom
`clear` verb, `fail > info > pass` severity precedence, and window-resolution code, all to manage
a slot that is at best a *glanceable hint*. A manual `clear` is also a *remembered norm*, the
opposite of this project's mechanical-floor ethos (cf. the `validate gate`).

A probe of the operator's tmux (3.4) collapsed all of it: `monitor-bell on` (the default) plus
the operator's existing `window-status-bell-style` already turn a **terminal bell** into a
per-window status-bar highlight, and tmux **auto-clears that flag when the window is visited**.
The hint and its release are native.

## Decision

Drop the custom window latch entirely. The window hint is **tmux's native bell flag**, tripped
by the `\a` `notify.sh` already writes to the agent's pane; **severity lives in the network
push**, not the window colour.

- **`fail`** → bell + push.
- **`pass`** → bell + push.
- **`info`** (permission/idle hooks) → bell only; **no push** — these are at-keyboard "which
  window is blocked" signals, and `idle_prompt` is too frequent to put on the phone.

The bell goes to the hook's controlling tty, so tmux flags the **agent's own window** with no
`-t` resolution, and **visiting the window clears it**. No `clear` verb, no severity precedence,
no false-clear, no stale-red to own. `notify.sh`'s level argument is back to the issue's
`pass`/`fail`/`info`.

This composes with the existing **FAIL-via-hook / PASS-via-command asymmetry**
(`validate_gate.py` fires `fail` deterministically in any session; `/validate` Phase 5 fires
`pass` only in a real validate session): the deterministic channel and the deliberate one both
ring the bell and push; neither paints a sticky colour.

## Why this over the alternatives

- **Custom per-window colour latch released by an explicit `clear`** (this ADR's first draft) —
  rejected: over-built for a slot that is only a glanceable hint. It needed window-resolution,
  `fail > info > pass` severity precedence, and a `clear` verb, and *still* left the operator to
  either remember to run `clear` (a remembered norm) or watch every project window rot. tmux's
  native bell flag gives the same per-window marker and auto-clears on visit, for free.
- **`pass` clears the window** — rejected: under one-window-per-project with concurrent panes, a
  peer `pass` false-clears a live fail.
- **Per-pane fail-set keyed on `$TMUX_PANE`** (window flagged iff any pane in its set is failing)
  — rejected: precise auto-clear, but adds shell-side set state and leaks **stale pane ids** when
  a pane is killed mid-fail. The colour need not be a faithful aggregate once the push owns
  reliability and the dashboard owns per-stream truth.
- **Auto-clear from the `dashboard` on all-green** — rejected: violates the dashboard's
  read-only / no-side-effects contract, and is out of #40 scope.

## Consequences

- The window flag is a **glanceable hint, not a source of truth**. Truth comes from the
  **network push** (never missed, AFK) and the **dashboard pane** (per-stream detail). A future
  reader who wants a sticky per-stream window colour should read the rejected alternatives first
  — the bell flag was a deliberate choice over them.
- `notify.sh` carries no `clear` level and sets no tmux options; it only rings the bell and (for
  `fail`/`pass`) pushes. The tmux transport is one line.
- **Relies on `monitor-bell on`** (tmux default, confirmed) and on the BEL reaching the agent's
  pane via the hook's controlling tty (the same path the first draft's bell used). The bell-flag
  mechanics themselves are **probe-verified on tmux 3.4**: a BEL to a *non-active* window's tty
  sets `#{window_bell_flag}` (status `!`), and visiting the window clears it.
- **Stale flag is bounded by tmux**, not by an operator running `clear`: it clears the next time
  the window is visited. No release machinery to own.
- **Open follow-ups** (out of #40): Channel B (the PR-state watcher) reuses the same transports;
  an optional per-pane border colour for in-window detail if the window-granular bell proves too
  coarse.
