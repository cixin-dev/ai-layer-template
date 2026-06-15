# Implement Report: settings.shared.json + auto-mode merge

**Plan**: `.agents/plans/settings-shared-auto-mode-merge.plan.md`
**Issue**: #27 (blocked-by #36 — now unblocked: `d4c0534` shipped the dangerous-push floor)
**Branch**: `feat/27-settings-shared-auto-mode-merge`
**Worktree**: `../ai-layer-template-feat-27-settings-shared-auto-mode-merge`

## Tasks completed

| Task | Status | Notes |
|------|--------|-------|
| 1. Create `.claude/settings.shared.json` | ✅ | Posture exactly per plan: `defaultMode: auto`, `ask: ["Bash(git push *)"]`, two Notification matcher blocks; no `allow`, no `deny`. Valid JSON. |
| 2. Add posture file to `setup_fixture` | ✅ | Heredoc-seeded into fixture; existing tests a–n stayed green (de-risk assumption confirmed). |
| 3. Add merge test cases shared-a–f (red) | ✅ | 10 failures at red bar, all from the unimplemented merge. |
| 4. Extend merge in `scripts/sync.sh` (green) | ✅ | All a–n + shared-a–f pass. |
| 5. Document posture in CONTEXT.md (US-18) | ✅ | Auto-approved / Gated / Why / Graduation prose under `### Unattended Autonomy`. |

## Validation results

- `bash scripts/sync.test.sh` → **All tests passed.** (a–n + shared-a–f)
- `python3 -c 'json.load(open(".claude/settings.shared.json"))'` → **ok** (valid JSON)
- `bash .claude/validate.sh` (→ `scripts/piv_check.sh`) → **PIV checks passed.**
- Manual E2E against a temp `CLAUDE_HOME` (never real `~/.claude`): dry-run plans the posture;
  real run writes `defaultMode: auto`, `ask: Bash(git push *)`, both Notification matchers;
  second dry-run is idempotent (no posture lines).

## Files changed

| File | Action |
|------|--------|
| `.claude/settings.shared.json` | CREATE — the inert versioned posture |
| `scripts/sync.sh` | UPDATE — read `settings.shared.json` (6th argv); additive graduation-aware merge of defaultMode/ask/allow + Notification (matcher-deduped); loud non-`auto` warning; posture folded into the single `.bak`/write gate; posture mirrored into the no-python3 fail-open branch |
| `scripts/sync.test.sh` | UPDATE — posture in `setup_fixture` + cases shared-a–f |
| `CONTEXT.md` | UPDATE — autonomy posture prose (US-18) |
| `docs/adr/0017-…md` | UPDATE — "Correction (2026-06-16)" note generalizing the never-re-add-graduated-`ask` invariant (carried into this branch from an uncommitted main edit, per user direction) |

## Tests written (new)

- **shared-a** fresh-fixture dry-run plans defaultMode/ask/both Notification matchers; no toolchain `allow`; no `settings.json` created.
- **shared-b** idempotent: after a real merge, second dry-run plans nothing.
- **shared-c** preservation: existing `Bash(gws drive:*)` and a non-auto `defaultMode: plan` survive; warning fires.
- **shared-d** loud no-op on **any** non-auto value (`default` and `plan`): warning printed naming the live value; `auto` not applied.
- **shared-e** graduation survives: live `allow` holding `Bash(git push *)` → `ask` entry not planned/added.
- **shared-f** fail-open + backup: `.bak` written before mutation; unparseable live `settings.json` → real run warns + exits 0, dry-run prints "would" lines.

## Deviations from plan

1. **ADR-0017 edit carried into the branch.** The plan didn't list `docs/adr/0017` as a file
   to change, but an uncommitted edit to it existed on `main` (the "2026-06-16 settings/sync
   slice" correction documenting this slice's general invariant). Per user direction (Phase 2
   AskUserQuestion), it was stashed off `main` and popped into this worktree so it ships in
   this slice's PR rather than stranding on `main`.
2. **Parse-failure `except` branch left posture-agnostic.** Plan Task 4.5 scopes fail-open
   posture mirroring to the **no-python3** branch only; the unparseable-`settings.json`
   `except` block (which needs a manual fix regardless) still emits only the hook fail-open
   lines. Test shared-f-ii asserts `warn`/`would` presence, which the existing lines satisfy.
   Minimal-change choice; the posture isn't separately surfaced there.

## Next step

`/validate .agents/plans/settings-shared-auto-mode-merge.plan.md` in a fresh session, then open a PR.
After merge: `/clean-worktree feat/27-settings-shared-auto-mode-merge`.
