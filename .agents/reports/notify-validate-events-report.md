# Report: Event-driven validate notification (tmux bell + ntfy) — Channel A

**Plan**: `.agents/plans/notify-validate-events.plan.md`
**Issue**: #40
**Branch**: `feat/40-notify-validate-events`

> **Post-grill re-cut (2026-06-16).** A second `grill-with-docs` pass before merge replaced the
> custom per-window colour latch (set on `fail`, released by an explicit `clear`) with tmux's
> **native bell flag** (tripped by the `\a` the bell already writes; auto-cleared when the window
> is visited). Severity moved entirely into the network push. `notify.sh` is back to the issue's
> `pass`/`fail`/`info` signature (no `clear`), and ADR-0021 was rewritten in place to record the
> slim design. This report reflects the final, merged-bound state.

## Tasks completed
| # | Task | Status |
|---|------|--------|
| 1 | `.claude/hooks/notify.sh` primitive (two transports, stdout-pure, fail-open) | ✅ |
| 2 | `.claude/hooks/notify.local.conf.example` (beside the hook, so notify.sh sources it / sync propagates it) | ✅ |
| 3 | `scripts/notify.test.sh` | ✅ |
| 4 | Wire FAIL into `validate_gate.py` (captured, never corrupts block JSON) | ✅ |
| 5 | Regression-test FAIL stdout purity + notify invocation in `validate_gate.test.sh` | ✅ |
| 6 | Wire PASS into `/validate` Phase 5 | ✅ |
| 7 | Repoint `settings.shared.json` Notification hooks → `notify.sh info` | ✅ |
| 8 | `.gitignore` + CI wiring + stale `sync.sh` note | ✅ |
| 9 | ADR-0021 rewrite + CONTEXT.md `notification` glossary entry (transport / source) | ✅ |

## Files changed
| File | Action |
|------|--------|
| `.claude/hooks/notify.sh` | CREATE (chmod +x) — slim: bell + push, no tmux options |
| `.claude/hooks/notify.local.conf.example` | CREATE — beside the hook |
| `scripts/notify.test.sh` | CREATE (chmod +x) |
| `.claude/hooks/validate_gate.py` | UPDATE — FAIL block path fires `notify.sh fail` |
| `scripts/validate_gate.test.sh` | UPDATE — test (c2) added |
| `.claude/commands/validate.md` | UPDATE — Phase 5 PASS step (step 4) |
| `.claude/settings.shared.json` | UPDATE — both Notification commands repointed to `notify.sh info` |
| `.gitignore` | UPDATE — ignore `notify.local.conf` |
| `.github/workflows/ci.yml` | UPDATE — `bash scripts/notify.test.sh` |
| `scripts/sync.sh` | UPDATE — no-python3 manual-snippet note text |
| `docs/adr/0021-notify-window-hint-is-tmux-native-bell-flag-severity-in-push.md` | CREATE (rewritten ADR-0021) |
| `CONTEXT.md` | UPDATE — `notification` term (transport / source) |

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
- **stdout purity** — red gate → stdout is exactly `{"decision": "block", "reason": …}`, no
  notify-arg leak.
- **no-op safety** — `env -u TMUX -u NTFY_TOPIC notify.sh info T M` → exit 0, empty stdout/stderr.
- **tmux bell flag (probe, tmux 3.4)** — a BEL written to a *non-active* window's tty sets
  `#{window_bell_flag}=1` (status shows `!`) under `monitor-bell on`, and **visiting the window
  clears it** (`flag → 0`). This is the entire "window hint" — no custom window option is set.

## Deviations from plan
1. **Task 5 leak assertion token.** The plan suggested `assert_not_contains "$stdout" 'fail'`.
   The block-JSON reason literally contains "Validation gate **failed**", so a lowercase `fail`
   substring check would false-fail. Replaced with `assert_not_contains "$stdout" 'Validate
   FAIL'` — the actual notify-arg leak marker, which the legitimate stdout never contains.
2. **Seed commit carried ADR-0021 too** — the Plan phase left an untracked `docs/adr/0021-…md`
   the plan cites as rationale; both travelled to the branch as the seed commit.
3. **Post-grill slim-down (this re-cut).** The shipped design dropped the custom window latch,
   `clear` level, and `fail>info>pass` severity precedence in favour of tmux's native bell flag;
   severity lives in the push. `notify.local.conf.example` moved into `.claude/hooks/` so the
   installed hook actually sources it. ADR-0021 rewritten; CONTEXT.md gained the `notification`
   term. `curl -d` → `--data-raw` (avoid a leading-`@` being read as a filename).

## Tests written
- `scripts/notify.test.sh` — (b) unconfigured no-op; (c) `fail` rings the bell, sets no tmux
  option, stdout pure; (d) `fail`/`pass` each push exactly once carrying title + message, and
  `pass` also rings the bell; (e) `info` rings the bell but **never** pushes. Every case asserts
  stdout purity.
- `scripts/validate_gate.test.sh` — test (c2): a red gate invokes `notify.sh fail` via the
  `VALIDATE_GATE_NOTIFY` seam; the shim log carries `fail` + `Validate FAIL` + the repo dir name,
  and stdout stays exact block JSON with no notify-arg leak.
