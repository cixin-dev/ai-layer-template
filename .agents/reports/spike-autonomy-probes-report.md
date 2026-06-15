# Implementation Report: spike-autonomy-probes

## Tasks Completed

### Task 1: Re-affirm binary ✅
- `~/.claude/local/node_modules/.bin/claude --version` → `2.1.177`
- `~/.bashrc:128` alias confirmed: `alias claude="~/.claude/local/claude"`
- Probe A / B / C(a) results in plan treated as authoritative (same binary, same machine)

### Task 2: Interactive Probe C(b) ✅ (with key deviation — see below)
- Scratch repo set up at `/tmp/probe-cb-9Qtnf4/repo`
- Local bare remote (`remote.git`), one commit pushed, one local, `defaultMode: "auto"` + `allow: ["Bash(git push *)"]` in `.claude/settings.json`
- Interactive session run; asked to `git push origin main`
- Push executed silently (`permissionDecisionMs=9`), no classifier interrupt

**Deviation**: Session was NOT in true auto mode. Debug log revealed:
> `settings defaultMode "auto" ignored — only policy/user/flag settings may grant auto mode (projectSettings and localSettings are repo-controllable)`

The probe put `defaultMode: "auto"` in project settings (`.claude/settings.json`). This is silently rejected. The session ran in default mode; the allow rule auto-approved in default mode (expected behavior). C(b) — whether the allow rule bypasses the auto-mode classifier — remains technically unresolved.

This finding is a deviation from the plan's assumptions (plan assumed project settings could grant auto mode for probe purposes).

### Task 3: Decide graduation mechanism ✅ (revised after Probe 1+2)
- **First pass**: chose graduate-by-removal on the assumption the classifier `soft_deny`s force/main push.
- **Revised**: that assumption was doc-only (`auto-mode defaults`), never observed at runtime. Probe 2 (below) refuted it. Final decision: **dangerous-push floor lives in `security_guard.py`, not the permission layer**; benign `git push` ask checkpoint stays un-graduated until that floor ships.

### Probe 1 (post-review, user-requested): user-scope `defaultMode:auto` ✅ VERIFIED GREEN
- Reversible A/B test of `~/.claude/settings.json` (backed up, set `defaultMode:auto`, ran, restored byte-identical, backup removed).
- project scope → `defaultMode "auto" ignored` WARN; user scope → no warning, `canEnterAuto=true`.
- Confirms `sync.sh` → user scope is valid; project/local scope cannot grant auto mode.

### Probe 2 (post-review, user-requested): classifier verdict on dangerous push 🔴 REFUTES floor
- True auto mode, no allow rule (graduate-by-removal posture). Classifier genuinely ran (6.5s / 10.5s model calls).
- `git push origin main` → debug log `Slow permission decision: 6551ms for Bash (mode=auto, behavior=allow)`; push landed.
- `git push --force origin main` → `(mode=auto, behavior=allow)`; force-push landed.
- Literal `behavior=allow` — not a swallowed soft_deny. Classifier is intent-aware; approves explicitly-instructed pushes.
- Caveat: headless + explicit instruction; autonomous-never-instructed push not elicited.

### Task 4: Record on issue #26 ✅
- First comment (now corrected): https://github.com/cixin-dev/ai-layer-template/issues/26#issuecomment-4705939590
- Correction comment with Probe 1+2 + revised NO-GO: https://github.com/cixin-dev/ai-layer-template/issues/26#issuecomment-4706126690

### Task 5: Resolve ADR-0017 + create ADR-0019 ✅ (revised)
- `docs/adr/0017-…md`: Status "Superseded by ADR-0019" with Probe-2 refutation cited.
- `docs/adr/0019-dangerous-push-floor-in-hook-not-permission-layer.md`: created (renamed from the graduate-by-removal draft) — decides the deterministic dangerous-push floor in `security_guard.py`.

## Validation Results
- No code gate (spike). Artifact validation:
  - `claude --version` → `2.1.177` ✅
  - Probes A/B/C(a) recorded (command + observation) on issue #26 ✅
  - Probe C(b): recorded with confound explanation and MOOT status given chosen mechanism ✅
  - ADR-0017 status unambiguous (Superseded by ADR-0019) ✅
  - ADR-0019 created and references back to ADR-0017/0018 ✅
  - Explicit go/no-go stated on issue #26 ✅

## Files Changed
| File | Action |
|------|--------|
| `docs/adr/0017-graduation-state-lives-in-live-dial-sync-must-not-regress-it.md` | Updated Status line |
| `docs/adr/0019-graduate-by-removal-not-by-allow.md` | Created |
| `.agents/plans/spike-autonomy-probes.plan.md` | Seeded as first commit |
| `.agents/reports/spike-autonomy-probes-report.md` | This report |

## Tests Written
None — spike; no production code in scope.

## Deviations from Plan
| Deviation | Rationale |
|-----------|-----------|
| Probe C(b) ("does a kept allow rule bypass the classifier?") never resolved — and made irrelevant | The real question was upstream of C(b): does the classifier gate dangerous push *at all*? Probe 2 showed it does not (`behavior=allow`). C(b)'s allow-vs-classifier distinction is moot when the classifier itself approves. |
| Plan's binary decision tree (graduate-by-allow vs graduate-by-removal) had no correct branch | Both share the refuted premise. The spike's job ("decide graduation mechanism") expanded to "relocate the dangerous-push floor out of the permission layer." User consulted; chose record-NO-GO + deterministic-floor. |
| Probe 1+2 added after initial Phase 4 | User-requested verification of `defaultMode:auto` activation surfaced the project-vs-user-scope constraint and, in turn, the classifier-not-a-floor finding. Verification-led course correction (CLAUDE.md: external-behavior claims need a probe, not docs). |

## Go/No-Go
🔴 **NO-GO (conditional)** — Do not ship graduation while dangerous push is gated only by the classifier or a static allow rule. **GO** once `security_guard.py` carries a probe-verified + tested dangerous-push floor (force-push + push-to-default-branch); until then `git push` stays on `ask`. Probe 1 confirms the auto-mode posture itself (user-scope `defaultMode:auto`) is sound.
