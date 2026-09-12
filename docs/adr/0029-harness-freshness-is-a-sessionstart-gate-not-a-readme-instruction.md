# Harness freshness is a SessionStart gate, not a README instruction

**Status:** Extends ADR-0007 (per-item symlinks) and ADR-0012 (hook copies) — their accepted
drift costs are now bounded by a mechanism, not by memory. Applies ADR-0010's floor/flow rule
to the install layer. Defers the marketplace-plugin route (revisit triggers below).

## Context

User scope reaches every downstream project through two channels: `~/.claude/{commands,skills}`
symlinks into source checkouts (this repo and the mattpocock checkout, ADR-0007) and real-file
hook copies in `~/.claude/hooks/` (ADR-0012). Both stay fresh only if the operator remembers
`git pull` + `bash scripts/sync.sh` (README "Apply"). ADR-0012 accepted hook drift because "the
practical drift window is narrow".

On 2026-09-13 that premise was found falsified: `sync.sh` had not run since 2026-06-13, so two
retroactives (#95's Grep-tool escape hatch; notify-on-FAIL) never reached the live hooks, and the
mattpocock checkout was 357 commits behind — `strategic-planning` (PR #103) invoked `to-spec` /
`to-tickets`, which did not exist locally. Nothing in the workflow could have noticed: the
freshness of the harness was the one thing the harness did not check.

## Decision

A **user-scope `SessionStart` hook**, `harness_freshness.sh`, makes staleness visible at every
session start in every downstream project. It discovers the source repos by resolving the
symlinks (never a hardcoded path) and reports one line per finding on stdout, so the line lands
in context:

- (a) a source checkout **behind its upstream** — fetch at most once per day (`FETCH_HEAD`
  mtime), bounded by `timeout`, fail open without network;
- (b) a source checkout **not on its default branch, or dirty** — the reverse hazard: every
  downstream session is running unreviewed edits;
- (c) a **dangling symlink** in `~/.claude/{commands,skills}`;
- (d) a hook copy **missing from or differing to** `<repo>/.claude/hooks/`.

Silent when green. **Always exits 0** in hook mode — a freshness warning must never block a
session. `--strict` (exit 1 on any finding) exists for the test seam and manual runs only; it is
deliberately **not** wired into `validate.sh`, because (b) fires by design during every
`retroactive/*` session, which works in the main checkout.

`sync.sh` installs it like the other hooks (copy, ADR-0012) and additively wires a
`SessionStart` block of its own — never appended to a foreign tool's block, whose installer may
rewrite it. `unsync.sh` is the exact inverse.

## Why a hook, given ADR-0010

ADR-0010 rejected a `SessionStart` nudge — for the *retroactive trigger*, a semantic judgment a
hook cannot make, and one that would fire unconditionally. Freshness is the opposite case: an
objective red/green comparison (`rev-list --count`, `cmp`, `-e`) with no judgment in it, silent
when green. It is exactly the "objective floor" ADR-0010 says hooks are for. The **decision** —
pull, relink, or leave a branch checked out — stays with the operator; the hook only surfaces
the state.

## Why not the marketplace plugin (deferred)

Matt Pocock now publishes `mattpocock-skills` as an official Claude Code marketplace plugin
(auto-update, namespaced). It would replace the per-item symlinks for that source — but it ships
skills this harness deliberately excludes (`implement`, `code-review`, `writing-for-agents`,
`domain-modeling`; see PR #105), and a probe on 2026-09-13 (11 headless cases, rc-asserted)
showed `skillOverrides` has **no effect on plugin skills** — a plugin skill set `off` still runs
and is still auto-invoked; `/plugin` is whole-plugin only. Per-item symlinks are the only
mechanism that keeps the intruders out today.

**Revisit when** any of: upstream splits the plugin into smaller units; Claude Code gains
per-skill control over plugin skills; upstream marks the intruders `disable-model-invocation`.
If reopened: the freshness gate gains a pin comparison against a template-owned
`marketplace.json` entry (`sha` pin; own/local marketplaces do not auto-update by default),
`strategic-planning` invocations become `mattpocock-skills:*`, and ADR-0004's "author's own
installer" premise is superseded.

## Rejected

- **A check in this repo's `validate.sh`** — protects only sessions in this checkout; the whole
  point is every downstream project.
- **Hardcoding the two source paths** — goes stale the moment a source moves or a third is
  added; the symlinks are the ground truth.
- **Fetching on every session start** — a network round-trip per session; the once-a-day
  throttle plus `timeout` bounds the cost, and a same-day miss is a day, not three months.
- **Auto-pull / auto-sync from the hook** — a hook that mutates a checkout at session start is
  the HEAD race (ADR-0024) by another name; surfacing beats acting.
- **A `Do-not` line alone** — prose that says "remember to sync" is the memory dependence this
  ADR removes. The `CLAUDE.md` line ships *alongside* the gate, for the judgment-shaped residue
  (act on the warning; never accept a "narrow window" without naming what bounds it).

## Consequence

ADR-0012's accepted cost is now bounded: hook-copy drift lasts at most until the next session
start, when it is named. The README "Apply" instruction survives as the *remedy*, not the
*safeguard*. First live run on this host reports the mattpocock checkout 357 behind; pulling it
dangles 9 links (upstream dropped `personal/`, renamed five) — relinking is by hand, per item,
and (c) is the backstop that names each one.
