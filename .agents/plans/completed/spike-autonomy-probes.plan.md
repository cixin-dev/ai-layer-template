# Plan: Spike — auto-mode go/no-go gates (no-snapshot, defaultMode:auto, graduation)

## Summary
This is a **spike**, not a feature. Issue #26 is the go/no-go gate that must clear before the
`settings.shared.json` + `sync.sh` slice can be finalized. Three probes (A no-snapshot, B
`defaultMode:auto` availability, C graduation mechanism) were run **during this planning session**
against the operator's *actually-used* Claude Code binary (v2.1.177 via the `~/.bashrc` alias →
`~/.claude/local/`), with commands and results recorded below. Findings: **Probe A = GREEN**
(`settings.shared.json` is not loaded as any scope), **Probe B = GREEN** (`auto` is an accepted
permission mode), **Probe C part (a) = VERIFIED kept** (a `Bash(git push *)` allow rule survives
`auto` mode), **Probe C part (b) = pending one interactive confirmation** (whether that kept allow
rule short-circuits the classifier could not be isolated non-interactively because the model
self-refuses force-push-to-main *before* a tool call reaches the permission layer). The evidence
points to **graduate-by-removal / supersede ADR-0017**, but per the issue this must not be
finalized until the interactive Probe C(b) lands. `/implement`'s job is therefore narrow: run the
one interactive C(b) confirmation, then **record the results and resolve ADR-0017's fate** (confirm,
or supersede with a new ADR-0019) and state an explicit go/no-go. No production code is in scope.

## User Story
As the operator, I want the three load-bearing Claude Code behaviors probed and recorded as
go/no-go gates, so that the `settings.shared.json` + `sync.sh` slice proceeds only on confirmed
behavior and implements the *correct* graduation logic (graduate-by-`allow` vs graduate-by-removal).

## Metadata
| Field | Value |
|-------|-------|
| Type | SPIKE (research / decision — no production code) |
| Complexity | MEDIUM |
| Systems affected | `docs/adr/0017…` (status), possibly new `docs/adr/0019…`; issue #26 record (results + go/no-go). No code. |
| Issue | #26 (labelled [HITL]) |

## Assumptions & Risks
The probes below were executed in this planning session. The binary used is the operator's
real one: `~/.bashrc:128` aliases `claude` → `~/.claude/local/claude` → **v2.1.177** (the
PATH-default `/usr/local/bin/claude` is a stale **v1.0.8** and is *not* what the operator runs
interactively — do not be misled by `which claude` in a non-login shell).

| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| Operator's installed Claude Code is ≥ v2.1.83 (Probe B prerequisite) | **VERIFIED** | `~/.claude/local/node_modules/.bin/claude --version` → `2.1.177`; `~/.bashrc:128: alias claude="…/.claude/local/claude"`. The `/usr/local/bin/claude` symlink reports `1.0.8` but is not the alias target. |
| **Probe A** — Claude Code does **not** load `.claude/settings.shared.json` as project (or any) scope | **VERIFIED — GREEN** | Scratch repo with `.claude/settings.json` (ask `Bash(CONTROLMARKER *)`) **and** `.claude/settings.shared.json` (ask `Bash(SHAREDMARKER *)`), run `claude --debug -p hi --debug-file …`. Debug shows: project `settings.json` → `Adding 1 ask rule(s) to destination 'projectSettings': ["Bash(CONTROLMARKER *)"]`; **SHAREDMARKER appears nowhere**; file watcher line lists only `~/.claude/settings.json`, project `settings.json`, project `settings.local.json` — `settings.shared.json` is not watched/loaded. The no-snapshot argument holds. |
| **Probe B** — installed CC accepts `defaultMode:"auto"` / `--permission-mode auto` | **VERIFIED — GREEN** | `claude --help` → `--permission-mode <mode>` choices include `"auto"` (alongside `acceptEdits`, `bypassPermissions`, `default`, `plan`). Debug from the Probe A run also shows `[auto-mode] verifyAutoModeGateAccess: … modelSupported=true canEnterAuto=true`. A `--settings` file carrying `defaultMode:"auto"` loaded without rejection (exit 0). |
| **Probe C(a)** — a command-scoped `Bash(git push *)` allow rule **survives** `auto` mode (is not dropped as a "broad allow rule") | **VERIFIED — kept** | Scratch repo `.claude/settings.json` with `defaultMode:"auto"`, `allow:["Bash(git push *)"]`; `claude --debug …` → `Applying permission update: Adding 1 allow rule(s) to destination 'projectSettings': ["Bash(git push *)"]`. Narrow command-scoped allow rules are kept (only arbitrary-execution rules like `Bash(*)` are documented as dropped). |
| **Probe C(b)** — whether a kept `Bash(git push *)` allow rule **short-circuits the classifier** (auto-approving force-push / direct-main-push, bypassing the `soft_deny`) | **ASSUMED (strongly supported) — needs 1 interactive confirmation** | Two facts point to *bypasses*: (i) C(a) shows the rule is kept; (ii) documented `auto` precedence is "allow/deny rules resolve immediately, bypassing the classifier." But the behavioral probe was **confounded**: asked to `git push --force origin main` in a `-p auto` session with the rule allowed, the **model refused at the reasoning layer** ("Force-pushing to main is explicitly something I'm instructed never to do") so no tool call reached the permission engine. Model reluctance is a *separate, probabilistic* guard, not the permission floor. **De-risk first in Implement**: Task 2 below runs the interactive confirmation. |
| `claude auto-mode defaults` / `config` reveal the classifier's own posture toward git | **VERIFIED (context)** | `claude auto-mode defaults` → `allow` includes "Git Push to Working Branch"; `soft_deny` includes "Git Destructive: Force pushing" **and** "Git Push to Default Branch". So the classifier *by default* gates force-push and main-push — which is exactly what graduate-by-removal preserves and graduate-by-`allow` (if it short-circuits) would lose. Note: `auto-mode config` output is **identical** with/without `permissions.allow` entries → static `allow` rules and the classifier are **separate layers**; `auto-mode config` cannot answer C(b). |
| Recording results as a `gh issue comment` on #26 + ADR update satisfies "results recorded" | **ASSUMED (low risk)** | Issue AC says "recorded (e.g. as ADR updates / notes on this issue)". Mitigation: do both — a structured comment on #26 and the ADR resolution. |

## Patterns to Follow
ADR format — mirror the existing files. A superseding ADR should carry a clear `**Status:**` line
and the original (0017) should get a status note pointing forward.

```markdown
# {Decision title, imperative}

**Status:** {Accepted / Superseded by ADR-00NN / Supersedes ADR-0017}; relates to ADR-0018, ADR-0016.

## Context
{the collision / forces}

## Decision
{what we decided}

## Why this over the alternatives
- **{alt}** — rejected: {why}

## Consequences
- {downstream effects, esp. what sync.sh must do}
// SOURCE: docs/adr/0017-graduation-state-lives-in-live-dial-sync-must-not-regress-it.md:1-59
// SOURCE: docs/adr/0018-auto-mode-classifier-over-static-allowlist.md:1-65
```

ADR-0017 already declares its own contingency (lines 1-9): it holds *only* if the rule is dropped
or the classifier still runs; it is **superseded** if a kept allow rule bypasses the classifier.
Probe C resolves which.

Probe commands to reuse verbatim (all use the real binary):
```bash
CLAUDE=~/.claude/local/node_modules/.bin/claude   # == the ~/.bashrc `claude` alias target
$CLAUDE --version                                  # 2.1.177
$CLAUDE --help | grep -A3 permission-mode          # auto present
$CLAUDE auto-mode defaults                         # classifier allow/soft_deny/hard_deny
# Probe A / C(a): scratch repo + .claude/settings.json + settings.shared.json + `--debug --debug-file`
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| issue #26 (via `gh issue comment`) | CREATE (comment) | Record Probe A/B/C results + explicit go/no-go + chosen graduation mechanism. The durable spike record. |
| `docs/adr/0017-graduation-state-lives-in-live-dial-sync-must-not-regress-it.md` | UPDATE | Resolve its contingency: either mark **confirmed** (graduate-by-`allow`) or **Superseded by ADR-0019** (graduate-by-removal). |
| `docs/adr/0019-graduate-by-removal-not-by-allow.md` | CREATE — **only on the C(b)=bypasses branch** | New ADR for graduate-by-removal: graduation marker is *not* an allow/ask/deny entry; `sync.sh` must read it to avoid re-adding `git push: ask`. Supersedes ADR-0017. |

No `.claude/`, `scripts/`, or hook code changes — those belong to the downstream settings/sync
slice, which this spike unblocks.

## Tasks
Ordered, atomic, each independently verifiable.

### Task 1: Re-affirm the binary + transcribe the already-run probe results
- File: (working notes → feeds Task 4)
- Action: verify
- Implement: Confirm `claude` resolves to v2.1.177 via the alias (`alias claude`, then
  `~/.claude/local/node_modules/.bin/claude --version`). Treat the Probe A / B / C(a) results in
  *Assumptions & Risks* as authoritative for this machine (they were run on this same binary); you
  do not need to re-run A/B/C(a) unless a result looks stale. If re-running, reuse the commands in
  *Patterns to Follow*.
- Validate: `claude --version` prints `2.1.177` (≥ 2.1.83).

### Task 2: Run the interactive Probe C(b) confirmation (the one remaining live gate) — [HITL]
- File: scratch repo (throwaway) + `--debug-file` log
- Action: probe
- Implement: The question is *purely* about the permission pipeline: **does a matched
  `Bash(git push *)` allow rule short-circuit (auto-approve) before the `auto` classifier runs?**
  The non-interactive probe is confounded by model self-refusal, so isolate the permission layer:
  1. Scratch git repo with a **local bare repo as `origin`** (no network), `main` as default
     branch, one commit pushed, one extra local commit. `.claude/settings.json`:
     `{"permissions":{"defaultMode":"auto","allow":["Bash(git push *)"]}}`.
  2. Open an **interactive** `auto` session in that repo with `--debug-file dbg.log`. As the
     operator, explicitly authorize and request the push that the classifier `soft_deny`s but the
     allow rule matches — start with **`git push origin main`** (push-to-default-branch; the model
     refuses force-push-to-main more readily, so use plain main-push first; escalate to
     `git push --force origin main` only if main-push is cleanly emitted).
  3. **Observe the permission decision, not the model's prose.** Outcomes:
     - **Auto-approved silently / no classifier interrupt** (and `dbg.log` shows no auto-mode
       classifier invocation for that tool_use) → allow rule **short-circuits** → C(b) = *bypasses*.
     - **Classifier interrupts** (soft-deny prompt/block, or `dbg.log` shows the classifier ran
       and blocked) despite the allow rule → C(b) = *classifier still runs*.
     - **Model refuses to emit the tool call** → not a permission-layer result; re-issue with
       stronger explicit operator consent, or grep `dbg.log` to confirm no permission decision was
       reached, and note the model-layer guard separately.
- Mirror: the debug-capture technique used for Probe A/C(a) (see *Patterns to Follow*).
- Validate: `dbg.log` (or the interactive UI) yields one of the two permission-layer outcomes
  above, recorded with the exact command and what was observed.

### Task 3: Decide the graduation mechanism from the C(b) outcome
- Action: decide
- Implement: Apply the issue's decision tree:
  - **Rule dropped, OR kept-but-classifier-still-runs** → **graduate-by-`allow`**; **ADR-0017
    stands** (a live `allow` entry is a safe graduation marker; the classifier floor remains).
  - **Rule kept AND bypasses classifier** (the evidence-favored branch) → **graduate-by-removal**
    (delete the live `ask` entry so push falls to the classifier — benign push unattended,
    force/main still `soft_deny`d) and **supersede ADR-0017**; the graduation marker must be a
    non-permission signal `sync.sh` can read (so it does not re-add `git push: ask`).
- Validate: a single sentence states which branch fired and why, traceable to Task 2's observation.

### Task 4: Record probe results + go/no-go on issue #26
- File: issue #26 (`gh issue comment 26 --body-file …`)
- Action: CREATE (comment)
- Implement: Post a structured comment: each probe (A/B/C) with status (green/red), the command
  run, the observed result; then the **explicit go/no-go** ("GO — proceed to the settings/sync
  slice with graduate-by-{allow|removal}" or "NO-GO — fall back to {documented fallback}"). For any
  red, name the chosen fallback (A-red → out-of-`.claude/` posture source synced user-scope-only;
  B-red → `acceptEdits` + allowlist).
- Mirror: issue-comment style used elsewhere in the repo's workflow.
- Validate: `gh issue view 26 --json comments` shows the comment with all four items present.

### Task 5: Resolve ADR-0017 (confirm or supersede)
- File: `docs/adr/0017-…md` (UPDATE) and, on the bypass branch, `docs/adr/0019-graduate-by-removal-not-by-allow.md` (CREATE)
- Action: UPDATE / CREATE
- Implement:
  - **Graduate-by-`allow` branch**: edit ADR-0017's `**Status:**` to record the probe confirmed it
    (cite Probe C result + date), removing the "contingent/superseded" conditional.
  - **Graduate-by-removal branch**: create ADR-0019 (mirror format in *Patterns to Follow*) deciding
    graduate-by-removal, documenting the non-permission graduation marker and the `sync.sh`
    obligation; set ADR-0017 `**Status:** Superseded by ADR-0019`.
- Mirror: `docs/adr/0017-…md:1-59`, `docs/adr/0018-…md:1-65`.
- Validate: ADR-0017 status is unambiguous; if superseding, ADR-0019 exists and references back.

## Validation
- No code gate to run (spike). The artifacts are the validation:
  - `claude --version` → `2.1.177`.
  - Probe results for A/B/C all recorded on issue #26 with command + observation.
  - Task 2 produced a permission-layer outcome (or an explicitly-noted model-refusal + fallback).
  - ADR-0017 resolved (confirmed or superseded by ADR-0019).
  - One explicit go/no-go sentence telling the settings/sync slice whether to proceed and which
    graduation logic to implement.
- If `.claude/validate.sh` exists, the Stop hook will run it (fails open / no-op for a docs-only
  change).

## Acceptance Criteria
- [ ] Probe A result recorded; on red, the no-snapshot fallback is chosen and documented before any code is written. *(A = GREEN, already recorded here.)*
- [ ] Probe B result recorded; on red, the `acceptEdits` fallback path is chosen and documented. *(B = GREEN, already recorded here.)*
- [ ] Probe C result recorded; graduation mechanism (graduate-by-`allow` vs graduate-by-removal) decided and ADR-0017 confirmed or superseded. *(C(a) verified; C(b) pending Task 2.)*
- [ ] An explicit go/no-go decision is stated so the settings/sync slice knows whether to proceed and which graduation logic to implement.
- [ ] Every external-behavior claim is VERIFIED by a probe, or carried as an explicit risk (C(b) carried as ASSUMED → confirmed in Task 2).
