# Plan: dashboard — Night Shift per-task phase + attempt count

## Summary
Extend `/dashboard` (`.claude/commands/dashboard.md`) with a **Night Shift — Loop State**
section: for each task the executor has touched, show its current loop **phase** and
**attempt count**, read straight from the durable loop-state store (`.night-shift/<N>.state`,
#68/#57) via the canonical `scripts/loop_state.sh` accessors — no second source of truth.
Terminal tasks are marked distinctly from in-flight ones: **🔴 escalated** (from the store's
`escalated` flag) and **✅ PR open** (derived from the open-PR list the dashboard already
gathers, matched by the `feat/{N}-*` branch convention). Because the store is gitignored and
lives in the executor's *own clone* (ADR-0024), the section honors `NIGHT_SHIFT_STATE_DIR`
and renders `(none)` when empty. This is a doc-only change to one slash-command file.

## User Story
As the operator, I want `/dashboard` to show each in-flight Night Shift task's loop phase and
attempt count — with terminal tasks (PR open / escalated) visibly distinct — so I can see at a
glance what the automation is doing without reading `.night-shift/` state files by hand.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | LOW |
| Systems affected | `.claude/commands/dashboard.md` (doc-only) |
| Issue | #64 |

## Assumptions & Risks
Every load-bearing claim, with how it was grounded.

| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| Enumerating `$STATE_DIR/*.state` + `loop_state.sh get-{phase,attempts,escalated}` extracts the right values, defaults absent/garbage **attempts & escalated** to `0` (get-phase returns empty for an absent key — render tolerates it; dispatch always writes phase first), and prints nothing for an empty/missing dir | **VERIFIED** | Probe: fixtures `64.state`(phase=implement,attempts=1), `99.state`(validate,3,escalated=1), `42.state`(phase only), `7.state`(attempts=oops). Loop printed `task=64 phase=implement attempts=1 escalated=0`, `task=99 … attempts=3 escalated=1`, `task=42 … attempts=0 escalated=0`, `task=7 … attempts=0`; a nonexistent dir printed nothing. |
| `loop_state.sh` resolves the dir from the **`NIGHT_SHIFT_STATE_DIR` env var** (not an arg), so the glob and the accessor must share it — recipe must `export` it | **VERIFIED** | `loop_state.sh:6` `STATE_DIR="${NIGHT_SHIFT_STATE_DIR:-.night-shift}"`; probe exported it and both agreed. |
| `.night-shift/` is gitignored and the executor runs in its **own clone** (ADR-0024), so the operator's main checkout usually has no state → the section must point at the clone via `NIGHT_SHIFT_STATE_DIR` and show `(none)` otherwise | **VERIFIED** | `.gitignore` contains `.night-shift/`; `git ls-files \| grep night-shift` returns only committed docs (plans/reports/ADRs), no `.state`; ADR-0024 Decision-2 ("dedicated Night Shift clone", `NIGHT_SHIFT_ROOT`). |
| Nothing removes `.state` files → they accumulate; the view must filter resolved tasks by **issue-open**, not list every historical task | **VERIFIED** | `grep -rn '\.state\|loop_state\|NIGHT_SHIFT_STATE_DIR\|\.night-shift' .claude/ scripts/` (excl `*.test.sh`) for `rm/remove/clean` → no matches. |
| PR-open is **not** in the store; derive it from the already-gathered open-PR list by matching branch `feat/{N}-*` | **VERIFIED** | `night_shift_run.sh:154` `branch="feat/${n}-${slug}"`; `_pr_open` gates the decider's `noop` (terminal); dashboard.md:81 already extracts `{N}` from `feat/{N}-{slug}`. |
| `escalated` is the only terminal signal that lives IN the store | **VERIFIED** | `loop_state.sh` `get-escalated`; `night_shift_run.sh:182-189` `escalate` → `set-escalated`. |
| `gh issue/pr list` limits (50/20) could omit a live task on a very large board → a live task misclassified "done" | **ASSUMED** (accepted risk) | Inherits the existing dashboard's own limits; #64 is explicitly "optional, low-cost observability". Noted in the doc; not fixed here. |
| Multi-clone Night Shift (serial→N concurrency, deferred to #63) means multiple `.night-shift/` dirs; a single `NIGHT_SHIFT_STATE_DIR` shows only the one it points at | **ASSUMED** (accepted limitation) | Concurrency is explicitly out of scope until #63 (ADR-0024 Decision-3). When it lands, the Phase 1D gather upgrades to a list of state dirs. |

## Patterns to Follow

**1. Doc-only extension of this same command** — the closest mirror is the prior slice that
added the Validate column. Same shape: extend Phase 1 gather, add a resolve/classify step, add
a render column/section, bump the description; validate with `validate.sh` + a probed recipe.
```
// SOURCE: .agents/plans/completed/dashboard-validate-column.plan.md:46-61 (Design + Files to Change)
```

**2. Bash-block gather + prose classification table** — dashboard.md mixes fenced bash for
data pulls (Phase 1) with markdown tables for the classification rules (Phase 2/3). Match it.
```bash
# SOURCE: .claude/commands/dashboard.md:15-18 (Phase 1A gather style)
gh issue list --state open --json number,title,labels,assignees --limit 50
gh pr list  --state open --json number,title,headRefName,isDraft,reviewDecision --limit 20
```
```
# SOURCE: .claude/commands/dashboard.md:75-79 (Phase 3 file-presence classification table style)
| Files present in worktree | Phase |
| No `.agents/plans/` or no plan file | PLAN |
```

**3. Branch → issue extraction convention** — already documented in this file; reuse it verbatim.
```
// SOURCE: .claude/commands/dashboard.md:81
If the branch name follows `feat/{N}-{slug}`, extract `{N}` as the linked Issue number.
```

**4. The verified enumeration recipe** (what Phase 1D will document — probe-confirmed above):
```bash
# Night Shift durable loop state. loop_state.sh reads NIGHT_SHIFT_STATE_DIR, so export it
# once and the glob + the accessors agree. Empty in the operator's main checkout — the
# executor runs in its own clone (ADR-0024); point the var at that clone's .night-shift.
export NIGHT_SHIFT_STATE_DIR="${NIGHT_SHIFT_STATE_DIR:-.night-shift}"
for f in "$NIGHT_SHIFT_STATE_DIR"/*.state; do
  [ -e "$f" ] || continue                       # no files -> section renders (none)
  n="$(basename "$f" .state)"
  printf '%s\t%s\t%s\t%s\n' "$n" \
    "$(bash scripts/loop_state.sh get-phase "$n")" \
    "$(bash scripts/loop_state.sh get-attempts "$n")" \
    "$(bash scripts/loop_state.sh get-escalated "$n")"
done
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/commands/dashboard.md` | UPDATE | Phase 1D gather step + new Phase 4 classify + Phase 5 render section (Render renumbered 4→5) + frontmatter description |

## Tasks
Ordered, atomic, each independently verifiable. All edits are to `.claude/commands/dashboard.md`.

### Task 1: Add Night Shift state to Phase 1 gather
- File: `.claude/commands/dashboard.md`
- Action: UPDATE — after Phase 1C ("Active worktrees"), add subsection **D. Night Shift loop
  state** containing the verified enumeration recipe (Pattern 4) and two one-line notes: the
  store is gitignored / lives in the executor's own clone (ADR-0024), so it's empty in the main
  checkout unless `NIGHT_SHIFT_STATE_DIR` points at the clone; and the var names a **single**
  dir — if multiple Night Shift clones ever run (#63 concurrency), only the pointed-at one is
  visible here (other clones' state dirs are out of view until the #63 gather upgrade).
- Mirror: `.claude/commands/dashboard.md:26-35` (Phase 1C block style)
- Validate: recipe already probe-verified (Assumptions row 1); `bash .claude/validate.sh` green.

### Task 2: Add Phase 4 — Classify Night Shift tasks (renumber Render to Phase 5)
- File: `.claude/commands/dashboard.md`
- Action: UPDATE — insert a new `## Phase 4 — Classify Night Shift loop state` before the render
  phase, and renumber the render heading `## Phase 4 — Render dashboard` → `## Phase 5 — Render
  dashboard`. The classification table (checked top-down), using the Phase 1D fields plus the
  Phase 1A open-issue / open-PR lists:

  | Condition (top-down) | Bucket / Status |
  |----------------------|-----------------|
  | Issue `N` **not** in the open-issues list | **Resolved** — omit from the table (state is stale after merge/close); count in the summary |
  | `escalated = 1` | **🔴 escalated** — terminal; needs human triage |
  | An open PR exists whose `headRefName` is `feat/{N}-*` | **✅ PR open #{pr}** — terminal; awaiting merge |
  | otherwise (issue open, not escalated, no PR) | **⏳ in-flight** — show the live phase + attempts |

  **Accepted limitation — ⏳ can't distinguish live from stalled.** A task that hit the retry
  cap without escalating, or whose loop crashed, stays issue-open / `escalated=0` / no-PR /
  `.state`-present — indistinguishable from a live task, so it renders ⏳ in-flight indefinitely
  (the store carries no cap-hit / stall signal). Accepted for this observability slice; a
  staleness cue (attempts ≥ MAX, or `.state` mtime) is a later enhancement.

- Mirror: `.claude/commands/dashboard.md:71-99` (Phase 3 resolve-step + mapping-table style)
- Validate: `bash .claude/validate.sh` green; classification matches the fixtures in the E2E check.

### Task 3: Add the render section + summary line
- File: `.claude/commands/dashboard.md`
- Action: UPDATE — in the (now Phase 5) render structure, add a `## 🌙 Night Shift — Loop State
  (N)` block after "Active Worktrees — PIV Progress", and add "N night-shift tasks in flight
  (M resolved)" to the closing one-line summary (the M resolved count is the landing spot for
  the resolved tasks omitted from the table per Task 2). Phase shown UPPER-cased to match the
  PIV phase column; `(none)` when empty.
  ```
  ## 🌙 Night Shift — Loop State (N)
  Durable per-task loop state (.night-shift/*.state; set NIGHT_SHIFT_STATE_DIR to the
  executor's clone to observe live state). In-flight tasks show their live phase; terminal
  tasks are marked. Example rows (illustrative — not real issues/PRs):
  | Task | Phase     | Attempts | Status                 |
  |------|-----------|----------|------------------------|
  | #42  | IMPLEMENT | 1        | ⏳ in-flight           |
  | #57  | VALIDATE  | 0        | ✅ PR open #83          |
  | #99  | VALIDATE  | 3        | 🔴 escalated — triage  |
  ```
- Mirror: `.claude/commands/dashboard.md:102-138` (Phase 4 render block + summary line)
- Validate: `bash .claude/validate.sh` green.

### Task 4: Update the frontmatter description
- File: `.claude/commands/dashboard.md`
- Action: UPDATE — append Night Shift loop state (phase + attempts) to the `description:` line.
- Mirror: `.claude/commands/dashboard.md:2`
- Validate: `bash .claude/validate.sh` green.

## Validation
```bash
bash .claude/validate.sh   # PIV checks pass (doc-only change keeps it green)

# Reader recipe — already probe-verified in planning; re-runnable with fixtures:
D="$(mktemp -d)"
printf 'phase=implement\nattempts=1\n'            > "$D/64.state"   # in-flight
printf 'phase=validate\nattempts=3\nescalated=1\n' > "$D/99.state"   # escalated (terminal)
printf 'phase=validate\nattempts=0\n'             > "$D/58.state"   # PR-open (terminal, via PR list)
export NIGHT_SHIFT_STATE_DIR="$D"
for f in "$D"/*.state; do [ -e "$f" ] || continue; n="$(basename "$f" .state)"; \
  printf '%s\t%s\t%s\t%s\n' "$n" \
    "$(bash scripts/loop_state.sh get-phase "$n")" \
    "$(bash scripts/loop_state.sh get-attempts "$n")" \
    "$(bash scripts/loop_state.sh get-escalated "$n")"; done
# expect: 58 validate 0 0 / 64 implement 1 0 / 99 validate 3 1
```

**End-to-end (the acceptance check).** The deterministic part stages from a fixture state dir:
run `/dashboard` with `NIGHT_SHIFT_STATE_DIR` pointed at a dir containing (a) an in-flight task,
(b) an `escalated=1` task, and (d) a `.state` file for a task whose issue is closed. Confirm the
rendered **🌙 Night Shift — Loop State** section:
- shows (a) with its phase + attempt count and ⏳ in-flight,
- marks (b) 🔴 escalated — visibly distinct from (a),
- omits (d) (resolved/stale) and counts it in the summary's `(M resolved)` tally,
- renders `(none)` when the dir is empty / unset.

Leg (c) — a task whose `feat/{N}-*` branch has an open PR rendering ✅ PR open #{pr} — is **not
fixture-stageable**: it comes from the live `gh pr list` output, not the state dir. Verify it
manually against a real open Night Shift PR (or with a stubbed `gh`); this leg is a live-state
check, not a deterministic one.

## Acceptance Criteria
- [ ] `/dashboard` shows each in-flight task's current loop phase (AC-1) — when `NIGHT_SHIFT_STATE_DIR` points at the executor's clone; `(none)` in the bare main checkout
- [ ] `/dashboard` shows each task's attempt count (AC-2) — same conditionality as AC-1
- [ ] Values read from the durable store via `loop_state.sh` — no separate source of truth (AC-3)
- [ ] Terminal tasks (🔴 escalated / ✅ PR open) are distinguishable from ⏳ in-flight (AC-4)
- [ ] Section honors `NIGHT_SHIFT_STATE_DIR` and renders `(none)` when empty (own-clone reality)
- [ ] `bash .claude/validate.sh` green
- [ ] Follows existing dashboard.md phase/gather/render patterns
- [ ] End-to-end behavior verified against the E2E check above
