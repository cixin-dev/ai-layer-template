# Report: Event-driven validate notification (tmux flag + ntfy) — Channel A

**Plan**: `.agents/plans/notify-validate-events.plan.md`
**Issue**: #40
**Branch**: `feat/40-notify-validate-events`

## Tasks completed
| # | Task | Status |
|---|------|--------|
| 1 | Create `.claude/hooks/notify.sh` primitive (two sinks, stdout-pure, fail-open) | ✅ |
| 2 | Create `.claude/notify.local.conf.example` | ✅ |
| 3 | Create `scripts/notify.test.sh` | ✅ |
| 4 | Wire FAIL into `validate_gate.py` (captured, never corrupts block JSON) | ✅ |
| 5 | Regression-test FAIL stdout purity + notify invocation in `validate_gate.test.sh` | ✅ |
| 6 | Wire PASS into `/validate` Phase 5 | ✅ |
| 7 | Repoint `settings.shared.json` Notification hooks → `notify.sh` | ✅ |
| 8 | `.gitignore` + CI wiring + stale `sync.sh` note | ✅ |

## Files changed
| File | Action |
|------|--------|
| `.claude/hooks/notify.sh` | CREATE (chmod +x) |
| `.claude/notify.local.conf.example` | CREATE |
| `scripts/notify.test.sh` | CREATE (chmod +x) |
| `.claude/hooks/validate_gate.py` | UPDATE — FAIL block path fires `notify.sh fail` |
| `scripts/validate_gate.test.sh` | UPDATE — test (c2) added |
| `.claude/commands/validate.md` | UPDATE — Phase 5 PASS step (step 4) |
| `.claude/settings.shared.json` | UPDATE — both Notification commands repointed |
| `.gitignore` | UPDATE — ignore `notify.local.conf` |
| `.github/workflows/ci.yml` | UPDATE — `bash scripts/notify.test.sh` |
| `scripts/sync.sh` | UPDATE — no-python3 manual-snippet note text |

## Validation results
Mechanical gate (all green):
```
notify.test.sh          All tests passed.
validate_gate.test.sh   All tests passed.
security_guard.test.sh  All tests passed.
sync.test.sh            All tests passed.
piv_check.test.sh       All tests passed.
settings.shared.json    valid JSON
```
End-to-end:
- **stdout purity** — red gate → stdout is exactly `{"decision": "block", "reason": …}`, no notify-arg leak.
- **no-op safety** — `env -u TMUX -u NTFY_TOPIC notify.sh info T M` → exit 0, empty stdout/stderr.
- **clear is safe** — `notify.sh clear` inside real tmux → exit 0, empty stdout (resets the flag).
- **`$HOME` expansion de-risk** (the plan's one ASSUMED claim) — **RESOLVED**: the rendered
  Notification command `"$HOME/.claude/hooks/notify.sh" info …` run through `bash -c` (with a
  temp `HOME` holding the installed hook) expands `$HOME` and executes notify.sh, RC=0, no stdout.

> Note: `bash .claude/validate.sh` (piv_check) only goes green once this report exists — it
> enforces "active plan ⇒ matching report". It is green after this file was written.

## Deviations from plan
1. **Task 5 leak assertion token.** The plan suggested `assert_not_contains "$stdout" 'fail'`.
   The block-JSON reason literally contains "Validation gate **failed**", so a lowercase
   `fail` substring check would false-fail. Replaced with `assert_not_contains "$stdout"
   'Validate FAIL'` — the actual notify-arg leak marker, which the legitimate stdout never
   contains. Same intent (prove notify args don't bleed into stdout), correct mechanics.
2. **Seed commit carried ADR-0021 too.** Besides the plan, the Plan phase left an untracked
   `docs/adr/0021-…md` that the plan repeatedly cites as its rationale. Both were committed as
   the branch's first (seed) commit so the ADR travels to main with the work.

No other deviations; all mirror references (validate_gate.py env-knob/block path, security_guard
shim+capture harness, validate_gate.test.sh tmpdir+asserts, settings.shared.json block shape)
were followed as written.

## Tests written
- `scripts/notify.test.sh` — cases (b) unconfigured no-op, (c) tmux fail (red+bell), (d) network
  push fires exactly once for fail and pass, (e1/e2) info severity (no downgrade of a live red;
  sets yellow when not red; never pushes), (f) clear releases both options without bell or push.
  Every case also asserts stdout purity.
- `scripts/validate_gate.test.sh` — test (c2): a red gate invokes `notify.sh fail` via the
  `VALIDATE_GATE_NOTIFY` seam, the shim log carries `fail` + `Validate FAIL` + the repo dir name,
  and stdout stays exact block JSON with no notify-arg leak.
