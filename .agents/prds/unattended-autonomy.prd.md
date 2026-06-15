# PRD — Unattended Autonomy (sandbox auto-approve + self-growing validation gate)

Status: draft-for-review
Source decisions: ADR-0003 (global sync, not copy-per-project), ADR-0009 (Validate as its own command, enforced by a Stop hook), ADR-0010 (System Evolution triggered by workflow handoff), ADR-0016 (dangerous-command policy in an exit-2 hook, not settings.deny)

## Problem Statement

The PIV Loop produces better code, and `/implement` already runs issues in parallel via
git-worktree isolation. But the operator's **attention** is the throughput ceiling, in two
distinct ways:

1. **Approval friction (per tool use).** Every read / search / test / edit / commit raises a
   permission prompt. With N parallel worktree agents, all N stall waiting for a human to click
   "approve" — so parallelism collapses back to serial human bandwidth. Ryan Lopopolo's framing
   applies directly: *every time you are forced to interact with the agent, the harness has
   failed.*
2. **Tracking friction (status polling).** The operator must actively go look at issue/PR state.
   `/dashboard` helps but is a **polling** model — it does not scale, because watching N agents
   means looking N times.

The root cause of (1) is concrete and was confirmed by inspection: the live user-scope config
`~/.claude/settings.json` has a `permissions.allow` list of exactly one entry
(`Bash(gws drive:*)`) and **no `defaultMode`** — so the default-prompt path fires on nearly
everything. This is not a missing architecture; it is an **unfilled allowlist**.

The deeper structural gap sits under (2): the System Evolution outer loop (`retroactive`) can
turn a bug into a CLAUDE.md rule, a command edit, a context update, or a plan-template change —
**but it has no path that strengthens the verification gate itself**. A prose rule relies on the
agent reading and obeying it (probabilistic); a check in `.claude/validate.sh` is enforced
deterministically by the `validate_gate.py` Stop hook (ADR-0009). For any mechanically-checkable
defect, the gate is strictly the better home, yet `retroactive` never sends defects there.

## Solution

Reframe the permission model from **verifying inputs** (approve each tool call) to **verifying
outputs** (let the sandbox run free; gate the boundary). The worktree provides the sandbox's
isolation half; the synced auto-approve posture (`acceptEdits` + the allowlist) is the other
half, and `.claude/validate.sh` (enforced by the Stop hook, ADR-0009) is the gate. Two changes
close the loop:

**A. Sandbox auto-approve, synced to user scope (fixes approval + tracking friction).**
Fill the allowlist and add interrupt-driven notification, distributed the same way the hooks
already are — versioned in this repo, synced once to user scope via `sync.sh` (ADR-0003), one
live copy, no per-project snapshots.

- Sandbox-internal operations (read/search/test/edit/commit) → auto-approved.
- Boundary operations (`git push`) → kept on `ask` as the single human checkpoint, graduating to
  `allow` once the gate earns trust.
- Dangerous-but-not-boundary operations (untrusted fetch-and-execute, `curl … | sh`) → denied in
  `security_guard.py` via an `exit(2)` block (ADR-0016), where the dangerous-command policy
  already lives. This is remote *code execution*, not data exfiltration — see Out of Scope.
- `Notification` hooks turn status from **polling** into **interrupt**: a desktop ping when an
  agent needs approval or finishes, replacing `/dashboard` polling.

**B. Self-growing validation gate (fixes the System Evolution gap).**
Add a highest-priority dimension to `retroactive` / `system-evolution`: *if the defect is
mechanically checkable, add a check to `.claude/validate.sh` (or the project's test suite)
before reaching for a prose rule.* This makes babysitting **self-liquidating**: every caught
defect grows the gate by one check. Gate growth is necessary but not sufficient for trust — the
signal that licenses graduating `git push` is a *falling escape rate* (a window with no new
mechanically-checkable defect reaching the codebase), not rising cumulative coverage.

From the operator's perspective, after this ships: parallel worktree agents run without
per-tool-use prompts; a red `validate.sh` blocks session-end (already true) and now also tends
to block `git push` defensively; the operator is pinged on exception rather than polling; and
every escaped-and-mechanical bug becomes a permanent gate check rather than a hopeful rule.

## User Stories

1. As the operator, I want sandbox-internal tool calls (read/search/test/edit/commit)
   auto-approved, so that N parallel worktree agents don't each stall on my click.
2. As the operator, I want `defaultMode: acceptEdits` at user scope, so that file edits and safe
   FS commands stop prompting across every project at once.
3. As the operator, I want `git push` to require approval (`ask`), so that I retain exactly one
   human checkpoint at the irreversible boundary.
4. As the operator, I want to be able to graduate `git push` from `ask` to `allow` by a one-line
   edit, so that full autonomy is a deliberate switch I flip when the gate has earned it.
5. As the operator, I want untrusted fetch-and-execute commands (`curl … | sh`, `wget … | bash`,
   bare `… | sh`, and `sh -c "$(curl …)"` / `eval` forms) denied by `security_guard.py` via an
   `exit(2)` block, so that the dangerous-command policy stays in one place (the hook) and —
   unlike an `exit(0)` JSON deny — overrides any matching `allow` rule (ADR-0016), rather than
   being split into `settings.deny`.
6. As the operator, I want a desktop notification when an agent needs approval, so that I don't
   have to watch a session to know it is blocked.
7. As the operator, I want a desktop notification when an agent goes idle/finishes, so that I
   stop polling `/dashboard` and react on interrupt instead.
8. As the operator, I want the permission + notification config **version-controlled in this
   repo**, so that it stays a versioned asset, not a hand-edited live file.
9. As the operator, I want that config synced to **user scope** via `sync.sh` (not copied
   per-project), so that there is one live source and no stale per-project snapshots (ADR-0003).
10. As the operator, I want the config source in a file Claude Code does **not** auto-load
    (`.claude/settings.shared.json`), so that it never doubles as project scope or propagates as
    a snapshot into scaffolded repos.
11. As the operator, I want `sync.sh` to **additively merge** these permissions into
    `~/.claude/settings.json` (union allow/ask, set `defaultMode` only if unset, dedupe
    Notification hooks by command), so that my existing user keys are preserved.
12. As the operator, I want the merge to reuse the existing `.bak` backup before writing, so that
    a bad sync is always recoverable.
13. As the operator, I want `sync.sh --dry-run` to print exactly which allow/ask entries,
    `defaultMode`, and Notification hooks it would add, so that I can review (比對) before
    mutating `~/.claude/`.
14. As the operator, I want the merge idempotent, so that re-running `sync.sh` converges and adds
    nothing already present.
15. As the operator, I want `retroactive` to ask first "is this defect mechanically checkable?"
    and, if yes, add a check to `.claude/validate.sh` or the project test suite, so that the
    deterministic gate catches the whole class next time (ADR-0009).
16. As the operator, I want prose rules (CLAUDE.md) treated as the **last** resort, used only
    when a defect needs design judgment / a human eye and cannot become a green/red check, so
    that I stop converting checkable bugs into hopeful reminders.
17. As the operator, I want the `system-evolution` skill to rank "strengthen the verification
    gate" as the first AI-Layer improvement to consider, so that the framing matches the new
    priority.
18. As the operator reviewing this change, I want the autonomy posture documented (what is
    auto-approved, what is gated, why), so that the risk trade-off is explicit and auditable.

## Implementation Decisions

**Modules built/modified**

- **`.claude/settings.shared.json`** (new, versioned). Inert data file — Claude Code auto-loads
  only `settings.json` and `settings.local.json`, never this name, so it carries no project-scope
  side effects. Contents: `permissions.defaultMode: "acceptEdits"`; `permissions.allow` (Read,
  Grep, Glob, Edit, and Bash patterns for the dev/test/git toolchain —
  `npm run/test`, `pnpm`, `pytest`, `uv run`, `git add/commit/status/log/diff/worktree`);
  `permissions.ask: ["Bash(git push *)"]`; `hooks.Notification` for `permission_prompt` and
  `idle_prompt` matchers running `notify-send`. No `deny` block — recursive deletes already live
  in `security_guard.py`, and fetch-and-execute denial moves there too.
- **`scripts/sync.sh`** (modified). Extend the existing Python merge step (the one that already
  wires `PreToolUse`/`Stop` hooks with `.bak` backup, idempotency, and `--dry-run`) to also read
  `.claude/settings.shared.json` and additively merge into `~/.claude/settings.json`:
  union `permissions.allow` / `permissions.ask` (dedupe, preserve existing entries such as
  `Bash(gws drive:*)`); set `permissions.defaultMode` only if absent (never clobber a user
  choice); append `hooks.Notification` blocks deduped by command. Reuse the existing single
  `.bak` backup and the existing `[sync] would …` dry-run line style. Fail open with a manual
  snippet if `python3` is missing or the file is unparseable, mirroring the current hook-wiring
  behavior.
- **`.claude/hooks/security_guard.py`** (modified). Two changes (ADR-0016): (1) add a
  `REMOTE_EXEC_PATTERNS` set for untrusted fetch-and-execute — a single pipe-to-shell pattern
  `\|\s*(sudo\s+)?(sh|bash|zsh)\b` (the `\b` avoids false positives like `| shasum`) that
  subsumes the curl/wget-specific cases, plus the `sh -c "$(…)"` / backtick and `eval`
  command-substitution forms. (2) Change the deny path for *all* cases (`.env`, recursive delete,
  and the new patterns) from `exit(0)` + stdout-JSON to `exit(2)` with the reason on **stderr**,
  so a deny overrides any matching `allow` rule rather than losing to it. Keep fail-open on parse
  error.
- **`.claude/commands/retroactive.md`** (modified). Two coupled edits so the file does not
  contradict itself: (1) Insert a new **Dimension 0** into Phase 2 ("Locate the gap") as a
  *yes/no gate*, not a priority rank: *Is the defect mechanically checkable (a lint rule, type
  check, test case, or grep assertion)? If yes → add the check to the project's
  `.claude/validate.sh` or its test suite so the Stop hook (ADR-0009) catches the class next
  time — a deterministic check always beats a prose rule.* (2) Amend **Phase 3** so its existing
  "pick the earliest layer in the workflow" rule is scoped to *prose* fixes only: Dimension 0
  decides checkable-vs-prose first; the earliest-layer ordering applies only once the fix has
  fallen through to a prose rule. Without (2), Phase 3's earliest-layer rule and Dimension 0's
  gate-first rule read as contradictory instructions.
- **`.claude/skills/system-evolution/SKILL.md`** (modified). Reorder the AI-Layer improvement
  framing so "strengthen the verification gate" is the first lever considered; prose rules
  (CLAUDE.md do-not entries) explicitly demoted to the fallback for judgment-shaped defects.

**Distribution boundary (ADR-0003)**

- Project-agnostic machinery synced to `~/.claude/`: the merged permissions + Notification hooks
  (from `settings.shared.json`), `security_guard.py`, `validate_gate.py`, commands, skills.
- Project-specific: each project's own `.claude/validate.sh` content (its lint/type/test/E2E
  commands) stays per-repo, versioned with that project's code. `settings.shared.json` defines
  the *posture*; each repo defines *what the gate runs*.

**Why not the obvious alternatives** (recorded so review doesn't relitigate)

- **`settings.local.json` as the source** — rejected: globally gitignored
  (`~/.config/git/ignore: **/.claude/settings.local.json`), so it cannot be a versioned asset;
  and its role is local-override, the opposite of a global-sync source.
- **A committed `settings.json` as the source** — rejected: Claude Code auto-loads it as project
  scope and it gets snapshotted into scaffolded repos, reintroducing the staleness problem
  ADR-0003 exists to kill.
- **`settings.deny` for dangerous commands** — rejected: one home for dangerous-command logic
  (the hook). `settings.deny` is deny-first and overrides `allow`; an `exit(0)` JSON hook is not,
  but an `exit(2)` hook is — so hardening the hook to `exit(2)` (ADR-0016) buys deny-first strength
  without splitting the policy across two mechanisms.

## Testing Decisions

Assert external behavior at the highest available seam. The mechanically-testable artifacts are
`sync.sh` (via `--dry-run`) and `security_guard.py` (via stdin/stdout contract).

- **Probe first (implement's opening step).** Before writing the merge, verify the load-bearing
  Claude Code behavior that fails *silently* if wrong: place a `settings.shared.json` carrying an
  observable rule in a scratch repo, open a session, and confirm Claude Code does **not** load it
  as project scope (the whole no-snapshot argument rests on this). The Notification matcher names
  (`permission_prompt`, `idle_prompt`) are already doc-confirmed and need no probe.

- **`scripts/sync.test.sh` — extend the dry-run assertions.** Drive `sync.sh --dry-run` against
  a fixture and assert the printed plan: (a) fresh state — would add each expected allow entry,
  the `git push` ask entry, `defaultMode: acceptEdits`, and both Notification hooks; (b)
  idempotency — against an already-merged `~/.claude/settings.json`, plans no permission/hook
  additions; (c) preservation — an existing unrelated allow entry (e.g. `Bash(gws drive:*)`) is
  never removed and `defaultMode` is not overwritten if already set; (d) backup — a real
  (non-dry) run writes `.bak` before mutating. Use the existing `CLAUDE_HOME` / `SYNC_REPO_DIR`
  test redirection so no real `~/.claude` is touched.
- **`security_guard.py` — fetch-and-execute deny assertions.** Feed PreToolUse JSON for
  `curl … | sh`, `wget … | bash`, `echo hi | sh`, and `bash -c "$(curl …)"`, and assert each
  **exits 2 with the reason on stderr** (not merely a JSON deny shape); assert the existing `.env`
  and `rm -rf` cases still exit 2 (behavior preserved under the new mechanism); feed a benign
  `curl -o file url` and a `| shasum` pipe and assert both **exit 0** (no false positive that
  would re-introduce approval friction).
- **`retroactive.md` / `system-evolution` SKILL — structural validation.** Assert Dimension 0
  exists in Phase 2 as a checkable-vs-prose gate **and** that Phase 3's earliest-layer rule is
  scoped to prose fixes (both edits present, so the file is not self-contradictory); assert the
  gate-first / prose-last ordering is present. These are prose; validate structurally, not
  behaviorally.

## Out of Scope

- A multi-repo control plane / orchestrator (Archon-like worktree DAG) — separate later project
  (ADR-0003).
- Changing `validate_gate.py` itself or the `/validate` push-on-green flow (ADR-0009) — unchanged.
- Auto-merging PRs without human review — explicitly **not** part of this PRD; `git push` stays
  on `ask` and PR review stays human until the operator deliberately graduates it.
- Phone/remote push notifications — `notify-send` (desktop, Linux) only; swapping in ntfy/Pushover
  is a later, trivial command substitution.
- Data *exfiltration* defenses (`curl --data @secret …`, `curl -T …` sending data **out**) —
  `security_guard.py` blocks untrusted fetch-and-execute (code coming *in*), not exfil; grep-based
  exfil rules would false-positive on every legitimate API POST. The residual is held by
  `git push: ask` + human PR review, not this hook.
- Any change to the PIV inner loop (`plan` / `implement`) beyond what parallel worktrees already
  provide.
- Auto-tuning the allowlist from transcripts (the upstream `fewer-permission-prompts` flow) — out
  of scope here; the seed allowlist is hand-authored, that tool can extend it later.

## Further Notes

- **Graduation is the whole point.** `git push: ask` → `allow` is the single **global** dial that
  converts "supervised autonomy" into "unattended autonomy." Because the `ask` entry is synced at
  user scope, this dial is all-or-nothing across projects — Claude Code evaluates `ask` before
  `allow`, so a per-project `allow` cannot override the global `ask` (graduation is necessarily
  global, not per-project). Flip it only when the *escape rate* has gone quiet — a recent window
  of work with no new mechanically-checkable defect reaching the codebase — not merely because
  cumulative gate coverage has grown. A recent fix means the gate was just shown to be leaky;
  that should *defer* graduation, not invite it.
- **Self-liquidating babysitting (the link between A and B).** A makes the agents run unattended;
  B makes the gate that guards them grow from each escaped defect. Without B, A is a static risk
  trade-off; with B, the required attention curve trends down over time. Ship both or the loop is
  open.
- **Accepted residual risk.** `defaultMode: acceptEdits` at user scope also applies in non-template
  repos where `validate_gate.py` fails open (no gate). Mitigated by: edits remain git-recoverable,
  `security_guard.py` blocks the irreversible deletes/exfil, and `git push` stays on `ask`. This is
  a conscious trade, not an oversight.
- **Suggested Ticket slicing** (confirm in `to-tickets`): (1) `settings.shared.json` +
  `sync.sh` merge extension + `sync.test.sh` coverage [AFK]; (2) `security_guard.py` exfil block +
  tests [AFK]; (3) `retroactive.md` Dimension 0 + `system-evolution` reorder [HITL — judgment
  wording review]. Slices 1–2 are independent; 3 is independent of both.
- Companion discussion sediment lives in the knowledge vault at
  `brainstorming/chat/20260615 Multi-Agent Orchestration 不再 babysit.md` — the reasoning trail
  behind this PRD.
