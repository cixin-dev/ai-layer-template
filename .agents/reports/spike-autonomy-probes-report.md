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

### Task 3: Decide graduation mechanism ✅
- **Graduate-by-removal chosen**
- Rationale: C(b) unresolved + asymmetric downside (bypass risk). Graduate-by-removal avoids the risk entirely: no allow rule placed on git push, classifier default applies.
- This is the "evidence-favored branch" from the plan, reached via the safety argument rather than a confirmed bypass observation.

### Task 4: Record on issue #26 ✅
- Comment posted: https://github.com/cixin-dev/ai-layer-template/issues/26#issuecomment-4705939590
- All probes A/B/C covered with command + observed result + rationale
- Explicit go/no-go stated: **GO with graduate-by-removal**

### Task 5: Resolve ADR-0017 + create ADR-0019 ✅
- `docs/adr/0017-…md`: Status updated to "Superseded by ADR-0019 (2026-06-15)" with probe citation
- `docs/adr/0019-graduate-by-removal-not-by-allow.md`: Created with full decision record

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
| Probe C(b) not definitively resolved | Project settings cannot grant auto mode (newly discovered). Probe ran in default mode. C(b) rendered MOOT by choosing graduate-by-removal (no allow rule in graduation). |
| C(b) classification: MOOT rather than confirmed-bypass | Could not observe true auto-mode permission-layer behavior. Graduate-by-removal is the safer choice regardless of C(b)'s resolution. |

## Go/No-Go
🟢 **GO** — Proceed to the settings/sync slice with graduate-by-removal graduation mechanism.
