# Graduate by removing the `ask` entry, not by promoting it to `allow`

**Status:** Accepted (2026-06-15); supersedes ADR-0017; relates to ADR-0018, ADR-0016.

## Context

ADR-0017 defined graduation as promoting the live `Bash(git push *)` entry from `ask` to
`allow` in `~/.claude/settings.json`, and made that allow entry the graduation *marker* that
`sync.sh` reads to suppress re-adding the `ask` rule. ADR-0017 declared itself contingent on
the graduation probe: it holds only if the auto-mode classifier still runs over a kept allow
rule (or if the rule is dropped outright). If the probe found the rule is kept *and* bypasses
the classifier, ADR-0017 must be superseded.

The probe (Issue #26, 2026-06-15) produced three findings:

1. **Probe C(a) = GREEN**: `Bash(git push *)` allow rules are kept by auto mode (not dropped as
   "broad allow rules").

2. **Probe C(b) = UNRESOLVED**: Whether a kept allow rule bypasses the auto-mode classifier
   could not be confirmed non-interactively. The interactive probe was confounded by a
   newly-discovered constraint — `defaultMode: "auto"` is silently ignored when set in project
   settings (`projectSettings`, `localSettings`); auto mode can only be granted by user/policy
   settings or the `--permission-mode auto` flag. The interactive session ran in default mode,
   not auto mode, so no permission-layer data about the classifier-vs-allow-rule interaction
   was captured.

3. **Critical new finding**: Project settings cannot grant auto mode. `sync.sh` targets user
   scope (`~/.claude/settings.json`), so merging `defaultMode: "auto"` from
   `settings.shared.json` into user scope remains valid. But `settings.shared.json` placed
   directly in a repo checkout cannot activate auto mode on its own.

C(b) remains unresolved. Granting that ADR-0018's intent is "classifier over static allowlist,"
a kept allow rule *probably* does not bypass the classifier — but the run-time behavior was not
directly observed. The graduate-by-allow model (ADR-0017) is therefore safe *if* that intent
holds, and unsafe if it does not. Given the asymmetric downside (unguarded force/main push),
the safer model is chosen.

## Decision

Graduation is **removal of the `ask` entry**, not promotion to `allow`.

- **Pre-graduation live state**: `permissions.ask` includes `"Bash(git push *)"`. Every push
  requires operator confirmation.
- **Graduation action**: operator removes `"Bash(git push *)"` from live `ask`. No entry is
  added to `allow`. Push falls to the auto-mode classifier's defaults (working-branch push
  allowed; push-to-default-branch and force push are `soft_deny`).
- **Graduation marker**: a non-permission top-level field `graduated.gitPush: true` written to
  `~/.claude/settings.json` by the operator at graduation time. This is the signal `sync.sh`
  reads to suppress re-adding the `ask` rule.

```json
// ~/.claude/settings.json after graduation
{
  "defaultMode": "auto",
  "graduated": { "gitPush": true },
  "permissions": {
    "ask": []          // "Bash(git push *)" removed; classifier now decides
  }
}
```

## Why this over the alternatives

- **Graduate-by-`allow` (ADR-0017)** — rejected: Probe C(b) could not confirm the classifier
  still runs over a kept allow rule in true auto mode. If the classifier is bypassed, push to
  default branch and force push lose their `soft_deny` guard after graduation — exactly the
  unguarded case ADR-0017 was contingent on not occurring. Asymmetric downside; safer to avoid.
- **Leave `ask` in place and rely on flag / session-level auto mode** — rejected: the `sync.sh`
  re-add problem from ADR-0017's context still applies. A live user settings file without the
  graduation marker would re-add `ask` on next sync, silently un-graduating the operator.
- **Graduation marker as a separate file** (`~/.claude/graduated`) — rejected: adds file sprawl
  and a second read path in `sync.sh`. A field in the same settings JSON `sync.sh` already
  reads is simpler and co-located with the state it guards.

## Consequences

- `sync.sh`'s merge gains a `graduated.gitPush`-specific check: before re-adding
  `"Bash(git push *)"` to `ask` from the shared file, it reads `graduated.gitPush` from the
  live user settings; if `true`, it skips the re-add. This is a narrower special case than
  ADR-0017's check (allow-entry presence) and harder to confuse with a routine merge artifact.
- `sync.test.sh` must assert two cases: (a) a live file without `graduated.gitPush` receives
  the `ask` rule from the shared file; (b) a live file with `graduated.gitPush: true` does
  **not** have the `ask` rule re-added.
- The graduation action becomes a two-step edit: remove `ask` entry AND set
  `graduated.gitPush: true`. Both must be present to be graduation-stable across syncs. The
  operator documentation (or a `graduate` command) must cover both steps together.
- A future reader who sees the empty `permissions.ask` and is tempted to re-add
  `"Bash(git push *)"` for safety should read this first: the absence is intentional, guarded
  by `graduated.gitPush`, and the classifier's `soft_deny` on push-to-default-branch remains
  active.
- ADR-0018's stated consequence — "`settings.shared.json` carries `defaultMode: auto`" — is
  valid as long as `sync.sh` merges to user scope (`~/.claude/settings.json`), not to project
  scope. Project settings cannot grant auto mode (probe finding, 2026-06-15).
