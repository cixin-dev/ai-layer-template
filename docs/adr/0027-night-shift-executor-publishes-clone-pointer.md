# The Night Shift executor publishes a `clone pointer` so read-only observers can locate its clone

**Status:** Accepted (2026-07-03); **extends** ADR-0024 (Night Shift executor runs in its own
clone). Additive, not a reversal — ADR-0024 stands unchanged.

## Context

ADR-0024 runs the Night Shift executor in a **dedicated clone** to resolve the HEAD race: the
automation's `main` and the human's `main` must never alias one checked-out HEAD. But that ADR
leaves the clone's *location* as external host knowledge — "an operational prerequisite… a
host-setup step." It documents **no path convention**.

Every read-only observer, though, needs that location. `/dashboard` runs in the operator's main
checkout and reads `.night-shift/*.state` to show per-task PIV progress — but the durable state
lives in the *executor's* clone, not the observer's checkout. #63 multi-clone tooling will have the
same need.

With no canonical source of truth for the location, PR 91 had the dashboard **guess a convention
path** (`~/night-shift/<repo>/`) and **mis-cited it to ADR-0024** (which documents no such path — a
Verification-led violation). Worse, a wrong guess degrades **silently**: the dir check fails, the
dashboard falls back to an empty in-checkout `.night-shift`, and renders `(none)` for a **live**
loop. A read-only observer must never authoritatively assert the wrong state.

The root cause is structural: the clone's location is external knowledge to every observer,
published nowhere canonical — only a runbook-hardcoded convention records it.

## Decision

**The executor publishes its own clone location — a `clone pointer`.** On every drain,
`night_shift_loop.sh` writes the single-line absolute path of its own clone's main checkout (the
`ROOT` it already computes via `git rev-parse --show-toplevel`) to a well-known, observer-reachable
file:

```
${XDG_STATE_HOME:-$HOME/.local/state}/night-shift/<repo>/clone-root
```

`<repo>` is the origin basename (`basename -s .git "$(git remote get-url origin)"`) — the *same*
derivation an observer runs from its own origin, so the two agree regardless of SSH-vs-HTTPS
remotes.

Key properties:

1. **Self-locating, not guessed.** The executor *publishes* where it is; observers *read* it. This
   replaces PR 91's convention guess for good.
2. **Written every drain, idempotent.** The location is always current truth — it cannot drift when
   the clone moves or is rebuilt. Written **before** the queue scan, so an idle-but-live clone still
   publishes (letting an observer distinguish "idle" from "absent").
3. **Points at the clone root, not the state dir.** The observer derives `$root/.night-shift`. The
   pointer is a general "here I am" locator, reusable by #63 tooling — not a dashboard-only
   state-dir pointer.
4. **Lives outside the clone, by necessity.** An observer that does not yet know where the clone is
   cannot read a file inside it (chicken-and-egg). `$XDG_STATE_HOME` — not `$XDG_CONFIG_HOME` —
   because this is machine-written runtime state, not user configuration.
5. **Observers degrade loudly.** Pointer missing, or pointing at a path that no longer exists → a
   loud hint ("can't find the executor — provisioned? clone moved?"), never a silent fallback.
   Pointer → an existing clone whose state dir is empty → "idle." State present → render. An
   explicit `NIGHT_SHIFT_STATE_DIR` still overrides everything (escape hatch).

## Consequences

- **Kills the silent false-negative at the root.** "I can't find it" and "it's idle" become
  distinct, observable states, instead of both collapsing to `(none)`.
- **The path and format become a small contract** between the executor and every observer —
  changing them is a coordinated change.
- **ADR-0024 is untouched.** The mis-citation was the dashboard's error, not 0024's; 0024 correctly
  documents no path. This ADR *adds* the missing decision rather than rewriting the old one — ADRs
  are append-only (see `CONTEXT.md`).
- **Invariant: one Night Shift clone per repo per host.** The `<repo>`-keyed pointer holds one
  location; two clones of the same repo on one host would clobber it — but they would also race on
  the remote `main`, so that configuration is already forbidden. Cross-org same-basename repos
  (`orgA/foo` vs `orgB/foo`) collide on the key too; acceptable for a single-operator, single-org
  host.
- **Sequencing.** This ADR records the decision; the executor-writes / dashboard-reads code lands in
  a separate PIV loop (Task 2), which also re-points the dashboard's citation from ADR-0024 to this
  ADR and removes the silent fallback.
